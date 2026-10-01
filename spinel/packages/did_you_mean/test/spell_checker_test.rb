require "did_you_mean"

# k's command names, and typos of them
DICTIONARY = %w[
  applications apps build_and_push clickhouse clickhouse_cli clickhouse_table_size contexts contexts_add
  contexts_remove contexts_use kibana config_set cnpg dashboard k logs logs_search pg pg_failover pg_password
  pg_pods pg_primaries pg_proxy pg_psql pg_resources pg_url pg_bloat pg_cache pg_index_usage pg_seq_scans
  pg_table_size pg_unused_indexes run console config config_edit config_get deploy elasticsearch_url env_edit
  releases rollback scale secrets secrets_edit secrets_get secrets_set secrets_unset secrets_create sh _exec
  nodes verify playground generate generate_application generate_deployment generate_resource node_pvcs
  node_failover node_purge_pvcs opensearch_url opensearch_dashboards opensearch_dashboard opensearch_overview
  restart redis redis_cli redis_sentinel_cli redis_failover redis_primaries redis_url redis_sentinel_url
  update
].freeze
TYPOS = %w[
  applicatons secrets_gett secret_get contexts_ad context pg_psq redis_cli2 deplyo relases rolback nodes_failover
  node_purge_pvc opensearch_overveiw clickhose clickhouse_table pg_unused_index logs_serach sh exec x kubect
  config_gte update2 generte playgroud restat scael build_push APPLICATIONS @apps ünïcode
].freeze

spell_checker = DidYouMean::SpellChecker.new(dictionary: DICTIONARY)
TYPOS.each { |typo| puts "#{typo}: #{spell_checker.correct(typo).inspect}" }

# Symbol dictionaries and input, as DidYouMean itself uses them
p DidYouMean::SpellChecker.new(dictionary: %i[first_name last_name email]).correct(:fist_name)
p DidYouMean::SpellChecker.new(dictionary: ["@foo", "@bar"]).correct("@fooo")
