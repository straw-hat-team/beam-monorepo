exclude = if Version.match?(System.version(), "< 1.20.0"), do: [:type_checker], else: []

ExUnit.start(exclude: exclude)
