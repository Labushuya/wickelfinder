-- ============================================================================
-- Wickelfinder — Migration 4: erweiterte Attribut-Tags
-- ============================================================================
-- Ausfuehren im Supabase-Dashboard -> SQL Editor -> Run.
-- Setzt Migration 1-3 voraus. Fuegt neue Werte zum place_tag-Enum hinzu und
-- erhoeht das Tag-Limit pro Bewertung.
--
-- Hinweis: ALTER TYPE ... ADD VALUE ist idempotent nur mit IF NOT EXISTS
-- (ab PG 12 unterstuetzt). Neue Enum-Werte koennen nicht in derselben
-- Transaktion verwendet werden — hier unproblematisch, da nur DDL.
-- ============================================================================

alter type place_tag add value if not exists 'paid';
alter type place_tag add value if not exists 'disposal';
alter type place_tag add value if not exists 'no_disposal';
alter type place_tag add value if not exists 'cramped';
alter type place_tag add value if not exists 'separate_room';
alter type place_tag add value if not exists 'sink';

-- Tag-Limit pro Bewertung von 4 auf 10 erhoehen (es gibt jetzt 10 Tags).
alter table ratings drop constraint if exists tags_max;
alter table ratings add constraint tags_max
  check (array_length(tags, 1) is null or array_length(tags, 1) <= 10);

-- ============================================================================
-- Migration 4 fertig.
-- ============================================================================
