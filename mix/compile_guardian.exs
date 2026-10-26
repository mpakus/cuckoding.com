defmodule Mix.Tasks.Compile.BossGuardian do
  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    source = "c_src/boss_guardian.c"
    target = "priv/native/boss_guardian"

    if :os.type() == {:unix, :darwin} and Mix.Utils.stale?([source], [target]) do
      File.mkdir_p!(Path.dirname(target))
      temporary = target <> ".#{System.pid()}.#{System.unique_integer([:positive])}"
      {:ok, file} = File.open(temporary, [:write, :exclusive])
      File.close(file)

      try do
        args = [
          "-std=c11",
          "-D_DARWIN_C_SOURCE",
          "-Wall",
          "-Wextra",
          "-Werror",
          "-O2",
          source,
          "-o",
          temporary
        ]

        case System.cmd("cc", args, stderr_to_stdout: true) do
          {_, 0} -> File.rename!(temporary, target)
          {output, _} -> Mix.raise("Native process helper compilation failed:\n" <> output)
        end
      after
        File.rm(temporary)
      end

      {:ok, []}
    else
      {:noop, []}
    end
  end
end
