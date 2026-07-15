# Migration history

Every schema change applied via the Supabase Dashboard gets its SQL saved
here as `NNNN_description.sql`, in order. This folder IS the schema history —
no CLI, no drift. RLS policies are part of each migration, on from table one.
