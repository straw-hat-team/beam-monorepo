ExUnit.start()

# Define Mox mock for system adapter
Mox.defmock(Trogon.Proto.SystemAdapter.Mock, for: Trogon.Proto.SystemAdapter)
