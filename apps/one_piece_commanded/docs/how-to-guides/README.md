# How-to Guides

## Import Test Support files  

1. Open your `test_helper.exs`, add the following code-snippet before `ExUnit.start()`:

    ```elixir
    one_piece_commanded_path = Mix.Project.deps_paths()[:one_piece_commanded]
    Code.require_file "#{one_piece_commanded_path}/test/test_support/command_handler_case.ex", __DIR__
    # Code.require_file "#{one_piece_commanded_path}/test/test_support/[other test support file name here].ex", __DIR__
    
    # ...
    
    ExUnit.start()
    ```

2. Verify that such files exists.
3. Use the Test Support Modules in your test.
