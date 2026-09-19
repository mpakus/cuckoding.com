defmodule CuckodingWeb.RunLogController do
  use CuckodingWeb, :controller

  alias Cuckoding.RunLog
  alias Cuckoding.Shell.Auth

  plug CuckodingWeb.LoopbackOnly

  def show(conn, %{"id" => run_id, "process_id" => process_id}) do
    if Auth.required?() and get_session(conn, :browser_authenticated) != true do
      CuckodingWeb.ShellController.unauthorized(conn)
    else
      download(conn, run_id, process_id)
    end
  end

  defp download(conn, run_id, process_id) do
    case RunLog.with_log(run_id, process_id, fn log ->
           conn =
             conn
             |> put_resp_content_type("text/plain")
             |> put_resp_header("cache-control", "no-store")
             |> put_resp_header("content-disposition", "attachment; filename=run-log.txt")
             |> send_chunked(200)

           Enum.reduce_while(RunLog.stream(log), conn, &send_chunk/2)
         end) do
      {:error, :log_unavailable} -> send_resp(conn, 404, "This run log is unavailable.")
      conn -> conn
    end
  end

  defp send_chunk(output, conn) do
    case chunk(conn, output) do
      {:ok, conn} -> {:cont, conn}
      {:error, _reason} -> {:halt, conn}
    end
  end
end
