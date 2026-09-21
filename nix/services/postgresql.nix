{
  config,
  lib,
  persist,
  pkgs,
  ...
}:
let
  postgresql = pkgs.postgresql_18;

in
{
  config.services.postgresql = {
    enable = true;
    package = postgresql;
    dataDir = "${persist}/var/lib/postgresql/${postgresql.psqlSchema}";
    extensions = ps: with ps; [ pg_repack ];

    settings = {
      # https://pgtune.leopard.in.ua/?dbVersion=18&osType=linux&dbType=web&cpuNum=24&totalMemory=32&totalMemoryUnit=GB&connectionNum=100&hdType=ssd
      # DB Version: 18
      # OS Type: linux
      # DB Type: web
      # Total Memory (RAM): 32 GB
      # CPUs num: 24
      # Connections num: 100
      # Data Storage: ssd
      max_connections = 100;
      shared_buffers = "8GB";
      effective_cache_size = "24GB";
      maintenance_work_mem = "2GB";
      checkpoint_completion_target = 0.9;
      wal_buffers = "16MB";
      default_statistics_target = 100;
      random_page_cost = 1.1;
      effective_io_concurrency = 200;
      work_mem = "67650kB";
      huge_pages = "try";
      min_wal_size = "1GB";
      max_wal_size = "4GB";
      max_worker_processes = 24;
      max_parallel_workers_per_gather = 4;
      max_parallel_workers = 24;
      max_parallel_maintenance_workers = 4;
    };
  };
}
