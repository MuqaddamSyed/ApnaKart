-- ============================================================
-- Delivery agent onboarding: store the agent's base address.
-- Run once in the Supabase SQL editor.
-- ============================================================

alter table delivery_agents
  add column if not exists address text;
