{:ok, _} = Application.ensure_all_started(:req)
ExUnit.start(exclude: [:integration])
