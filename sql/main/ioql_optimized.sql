CREATE OR REPLACE FUNCTION ioql_exec_query_record_sql(query ioql_query)
    RETURNS TEXT LANGUAGE PLPGSQL STABLE AS
$BODY$
DECLARE
    sql_code TEXT;
BEGIN
    --TODO : cross-epoch queries can be optimized much more than a simple limit. 
    SELECT format(
      $$ SELECT *
         FROM (%s) AS union_epoch
         LIMIT %L
      $$,
          string_agg('('||code_epoch.code||')', ' UNION ALL '),
          query.limit_rows)
    INTO sql_code
    FROM (
      SELECT CASE WHEN  NOT query.aggregate IS NULL THEN
                    ioql_query_agg_sql(query, pe)
                  ELSE
                     ioql_query_nonagg_sql(query, pe)
                  END AS code
      FROM partition_epoch pe
      WHERE pe.hypertable_name = query.namespace_name
    ) AS code_epoch;

    IF NOT FOUND THEN
        RETURN format($$ SELECT * FROM no_cluster_table(%L) $$, _query);
    END IF;

    RAISE NOTICE E'Cross-node SQL:\n%\n', sql_code;
    RETURN sql_code;
END
$BODY$;

CREATE OR REPLACE FUNCTION ioql_exec_query_record_cursor(query ioql_query, curs REFCURSOR)
    RETURNS REFCURSOR AS $BODY$
BEGIN
    OPEN curs FOR EXECUTE ioql_exec_query_record_sql(query);
    RETURN curs;
END
$BODY$
LANGUAGE plpgsql STABLE;


CREATE OR REPLACE FUNCTION ioql_exec_query(query ioql_query)
    RETURNS TABLE(json TEXT) AS $BODY$
BEGIN
    --  IF to_regclass(get_cluster_name(get_namespace(query))::cstring) IS NULL THEN
    --    RETURN QUERY SELECT * FROM no_cluster_table(query);
    --    RETURN;
    --  END IF;
    RETURN QUERY EXECUTE format(
        $$
    SELECT row_to_json(ans)::text
    FROM (%s) as ans
    $$, ioql_exec_query_record_sql(query));
END
$BODY$
LANGUAGE plpgsql STABLE;



