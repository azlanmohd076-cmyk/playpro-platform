-- PlayPro — reload PostgREST schema cache after live player projection repair.
-- No table/column/data changes. Safe operational refresh only.
NOTIFY pgrst, 'reload schema';
