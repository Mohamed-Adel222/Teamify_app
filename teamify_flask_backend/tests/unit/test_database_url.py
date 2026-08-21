from config import resolve_database_url, sqlalchemy_engine_options


EXTERNAL = (
    "postgresql://u:p@dpg-d8dpcfjbc2fs73ejaamg-a.oregon-postgres.render.com/teamify"
)
INTERNAL = "postgresql://u:p@dpg-d8dpcfjbc2fs73ejaamg-a/teamify"


class TestResolveDatabaseUrl:
    def test_postgres_scheme_normalized(self):
        url = resolve_database_url("postgres://u:p@localhost/db")
        assert url.startswith("postgresql://")

    def test_sqlite_unchanged(self):
        assert resolve_database_url("sqlite:///app.db") == "sqlite:///app.db"

    def test_keeps_external_render_host_by_default(self):
        assert resolve_database_url(EXTERNAL, use_internal=False) == EXTERNAL

    def test_opt_in_internal_rewrite(self):
        assert resolve_database_url(EXTERNAL, use_internal=True) == INTERNAL

    def test_strips_sslmode_when_switching_to_internal(self):
        url = resolve_database_url(EXTERNAL + "?sslmode=require", use_internal=True)
        assert "sslmode" not in url
        assert url.startswith("postgresql://u:p@dpg-d8dpcfjbc2fs73ejaamg-a/")


class TestEngineOptions:
    def test_sqlite_has_no_ssl(self):
        opts = sqlalchemy_engine_options("sqlite:///app.db")
        assert opts["pool_pre_ping"] is True
        assert "connect_args" not in opts

    def test_internal_render_disables_ssl(self):
        opts = sqlalchemy_engine_options(INTERNAL)
        assert opts["connect_args"]["sslmode"] == "disable"

    def test_external_postgres_requires_ssl(self):
        opts = sqlalchemy_engine_options(EXTERNAL)
        assert opts["connect_args"]["sslmode"] == "require"
        assert opts["connect_args"]["connect_timeout"] == 10
