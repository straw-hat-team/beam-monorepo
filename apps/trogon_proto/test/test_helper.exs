ExUnit.start()

# Start the mox application for async tests
Application.ensure_all_started(:mox)

# Define Mox mock for system adapter
Mox.defmock(Trogon.Proto.SystemAdapter.Mock, for: Trogon.Proto.SystemAdapter)
Mox.set_mox_global()
