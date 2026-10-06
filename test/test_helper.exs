ExUnit.start()

# A plugin is a folder with a manifest.json listing its files; Pepe compiles them at install time.
# Load them the same way here, so the tests run the exact files that get published.
for manifest <- Path.wildcard(Path.expand("../*/manifest.json", __DIR__)) do
  dir = Path.dirname(manifest)

  for file <- manifest |> File.read!() |> Jason.decode!() |> Map.fetch!("files") do
    Code.require_file(Path.join(dir, file))
  end
end
