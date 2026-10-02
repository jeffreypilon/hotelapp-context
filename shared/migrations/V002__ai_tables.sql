-- =============================================================================
-- V002__ai_tables.sql
--
-- Storage owned by hotelapp-ai-service: the document corpus, its embedded
-- chunks, and evaluation history. Specified by shared/ai-enablement-overview.md
-- and stacks/ai-service/architecture-specification.md. If this file and those
-- documents disagree, the documents are right and this file is wrong.
--
-- Target: PostgreSQL 18.6 WITH pgvector. The official postgres images ship no
-- third-party extensions, so this migration requires the pgvector/pgvector:pg18
-- image (or a host with pgvector installed) -- see
-- stacks/ai-service/environment-setup-guide.md.
--
-- Applied by Flyway ONLY, like every other migration here. The AI service never
-- applies DDL; it asserts at startup that these objects exist and fails fast if
-- they do not, which is the same posture as Spring Boot's ddl-auto=validate.
-- Forward-only and immutable once merged.
--
-- BOUNDARY: every table here is prefixed ai_, and the AI service's database role
-- is granted rights on these and NOTHING else. Business data reaches that
-- service over REST, never over SQL -- the constraint the whole component is
-- built around. The prefix makes the boundary legible from the schema alone.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Extensions
-- -----------------------------------------------------------------------------

-- Supplies the vector type, its distance operators, and the HNSW index method.
CREATE EXTENSION IF NOT EXISTS vector;


-- -----------------------------------------------------------------------------
-- ai_documents -- one row per source document in the corpus
-- -----------------------------------------------------------------------------

CREATE TABLE ai_documents (
  id            uuid          PRIMARY KEY DEFAULT uuidv7(),
  source_path   varchar(500)  NOT NULL UNIQUE,
  title         varchar(300)  NOT NULL,
  property_id   uuid          NULL,
  content_hash  char(64)      NOT NULL,
  chunk_count   integer       NOT NULL DEFAULT 0 CHECK (chunk_count >= 0),
  ingested_at   timestamptz   NOT NULL DEFAULT now(),
  updated_at    timestamptz   NOT NULL DEFAULT now()
);

-- property_id is deliberately NOT a foreign key to properties(id).
--
-- A FK here would be the one place this service's schema depends on a business
-- table, and the dependency would be enforced in the wrong direction: deleting a
-- property would then be blocked by, or cascade into, AI storage. It is a
-- scoping hint for retrieval filtering ("documents about Harborview Grand"),
-- resolved by the service against the REST API, and NULL for corpus-wide
-- documents such as brand-level policy.
COMMENT ON COLUMN ai_documents.property_id IS
  'Scoping hint only. Intentionally not an FK -- see V002 comments.';

-- content_hash makes ingestion idempotent: a document whose hash is unchanged is
-- skipped rather than re-chunked and re-embedded, which is what keeps a re-run
-- of `ingest` free rather than another bill from the embeddings provider.
COMMENT ON COLUMN ai_documents.content_hash IS
  'SHA-256 of the source bytes. Unchanged hash means skip re-ingestion.';


-- -----------------------------------------------------------------------------
-- ai_chunks -- the retrievable units, with both retrieval representations
-- -----------------------------------------------------------------------------

CREATE TABLE ai_chunks (
  id            uuid          PRIMARY KEY DEFAULT uuidv7(),
  document_id   uuid          NOT NULL REFERENCES ai_documents (id) ON DELETE CASCADE,
  chunk_index   integer       NOT NULL CHECK (chunk_index >= 0),
  heading_path  varchar(500)  NULL,
  content       text          NOT NULL,
  token_count   integer       NOT NULL CHECK (token_count > 0),
  embedding     vector(1536)  NOT NULL,
  created_at    timestamptz   NOT NULL DEFAULT now(),

  CONSTRAINT ai_chunks_document_index_key UNIQUE (document_id, chunk_index)
);

-- The embedding dimension is PINNED at 1536, matching text-embedding-3-small
-- (and -3-large at its default). This is a real constraint, not an arbitrary
-- one: pgvector requires a fixed dimension to build an HNSW index, so the column
-- cannot be provider-agnostic.
--
-- CONSEQUENCE: swapping to an embedding model of a different dimension is a
-- MIGRATION, not a configuration change. It needs a new V-numbered file altering
-- this column and a full re-ingest, because every stored vector becomes
-- meaningless. The offline Ollama fallback must therefore use a 1536-dimension
-- model, or ship that migration. Flagged in
-- stacks/ai-service/dependency-policy.md under Maintenance.
COMMENT ON COLUMN ai_chunks.embedding IS
  'vector(1536) -- pinned to the embedding model. Changing models of a different '
  'dimension requires a new migration and a full re-ingest.';

-- heading_path carries the document section a chunk came from ("Cancellation >
-- Flexible rates"), so a citation can name where an answer lives rather than
-- only which file it came from. Rendering it is a pure function in the service's
-- domain/ layer.
COMMENT ON COLUMN ai_chunks.heading_path IS
  'Section path within the source document, for citations.';

-- The sparse half of hybrid retrieval. Generated rather than maintained by the
-- application, for the same reason reservations.stay_period is generated in
-- V001: a derived column the application can forget to update is a derived
-- column that will eventually be wrong.
ALTER TABLE ai_chunks
  ADD COLUMN content_tsv tsvector
  GENERATED ALWAYS AS (to_tsvector('english', content)) STORED;

COMMENT ON COLUMN ai_chunks.content_tsv IS
  'Generated. Sparse (BM25-style) half of hybrid retrieval; fused with the '
  'dense vector results by Reciprocal Rank Fusion in the service.';


-- -----------------------------------------------------------------------------
-- ai_eval_runs -- evaluation history
--
-- Persisted so answer quality over time is queryable rather than remembered.
-- The RAGAS suite is a CI gate with committed floors; this is its record.
-- -----------------------------------------------------------------------------

CREATE TABLE ai_eval_runs (
  id               uuid          PRIMARY KEY DEFAULT uuidv7(),
  run_at           timestamptz   NOT NULL DEFAULT now(),
  git_sha          char(40)      NULL,
  generation_model varchar(100)  NOT NULL,
  embedding_model  varchar(100)  NOT NULL,
  question_count   integer       NOT NULL CHECK (question_count > 0),
  metrics          jsonb         NOT NULL,
  passed           boolean       NOT NULL
);

-- metrics is jsonb rather than typed columns on purpose: the metric set is
-- expected to change as the suite matures, and adding a metric should not be a
-- migration. Retrieval and generation metrics are reported separately inside it
-- (context precision/recall vs. faithfulness/answer relevancy) because they fail
-- independently and can mask each other.
COMMENT ON COLUMN ai_eval_runs.metrics IS
  'RAGAS metric values. Retrieval and generation reported separately.';


-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------

-- Dense retrieval. HNSW over cosine distance, matching the operator the service
-- queries with (<=>). An index built for a different operator class is simply
-- not used, silently -- which is why stacks/ai-service/testing-standards.md
-- requires an EXPLAIN test asserting this index is chosen, the same way the
-- availability query's plan is asserted in the Spring Boot suite.
CREATE INDEX ai_chunks_embedding_hnsw_idx
  ON ai_chunks USING hnsw (embedding vector_cosine_ops);

-- Sparse retrieval.
CREATE INDEX ai_chunks_content_tsv_idx
  ON ai_chunks USING gin (content_tsv);

-- Chunk lookup by document, and the FK's own supporting index.
CREATE INDEX ai_chunks_document_id_idx
  ON ai_chunks (document_id);

-- Retrieval scoped to one property.
CREATE INDEX ai_documents_property_id_idx
  ON ai_documents (property_id)
  WHERE property_id IS NOT NULL;

-- Most recent evaluation runs first.
CREATE INDEX ai_eval_runs_run_at_idx
  ON ai_eval_runs (run_at DESC);
