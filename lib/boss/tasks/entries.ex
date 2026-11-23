defmodule Boss.Tasks.Entries do
  @moduledoc """
  Append-only task comments, specification update notes, and agent cycle logs.
  Preserves immutable history alongside the task's current state.
  """
  import Ecto.Query
  alias Boss.Agents.Roles
  alias Boss.Repo
  alias Boss.Tasks.Entry

  @max_summary 240
  @max_body 8_000

  def table_ready? do
    Repo.query!(
      "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type='table' AND name='task_entries')"
    ).rows == [[1]]
  rescue
    _ -> false
  end

  def list_for_task(project_id, task_id, limit \\ 100)
      when is_integer(project_id) and is_integer(task_id) do
    if table_ready?() do
      Entry
      |> where([e], e.project_id == ^project_id and e.task_id == ^task_id)
      |> order_by([e], desc: e.id)
      |> limit(^limit)
      |> Repo.all()
      |> Enum.map(&present/1)
    else
      []
    end
  rescue
    _ -> []
  end

  def add_comment(project_id, task_id, attrs)
      when is_integer(project_id) and is_integer(task_id) and is_map(attrs) do
    if table_ready?() do
      role = to_string(attrs[:author_role] || attrs["author_role"] || "owner")
      kind = to_string(attrs[:kind] || attrs["kind"] || "comment")
      raw_text = to_string(attrs[:body] || attrs["body"] || "")
      raw_summary = attrs[:summary] || attrs["summary"]

      clean_body = sanitize_text(raw_text, @max_body)

      summary =
        cond do
          is_binary(raw_summary) and String.trim(raw_summary) != "" ->
            sanitize_line(raw_summary, @max_summary)

          String.trim(clean_body) != "" ->
            first_line = clean_body |> String.split(~r/\R/u, parts: 2) |> hd()
            sanitize_line(first_line, @max_summary)

          true ->
            ""
        end

      if summary == "" do
        {:error, :empty_comment}
      else
        record_attrs = %{
          project_id: project_id,
          task_id: task_id,
          delivery_id: attrs[:delivery_id] || attrs["delivery_id"],
          spec_revision_id: attrs[:spec_revision_id] || attrs["spec_revision_id"],
          author_role: role,
          agent_id: attrs[:agent_id] || attrs["agent_id"],
          model_id: attrs[:model_id] || attrs["model_id"],
          kind: kind,
          cycle: attrs[:cycle] || attrs["cycle"],
          stage: attrs[:stage] || attrs["stage"],
          summary: summary,
          body: clean_body
        }

        case %Entry{} |> Entry.changeset(record_attrs) |> Repo.insert() do
          {:ok, saved} ->
            if not Repo.in_transaction?(), do: Boss.Tasks.broadcast(project_id)
            {:ok, present(saved)}

          {:error, _} ->
            {:error, :invalid_comment}
        end
      end
    else
      {:error, :unavailable}
    end
  end

  def record_delivery_step(delivery, step, receipt) do
    if table_ready?() do
      case step_entry(delivery, step, receipt) do
        nil ->
          :ok

        attrs ->
          %Entry{}
          |> Entry.changeset(
            Map.merge(attrs, %{
              project_id: delivery.project_id,
              task_id: delivery.task_id,
              delivery_id: delivery.id,
              cycle: step.cycle,
              stage: step.kind
            })
          )
          |> Repo.insert()

          :ok
      end
    else
      :ok
    end
  rescue
    _ -> :ok
  end

  defp step_entry(delivery, %{kind: "plan"} = step, %{"status" => "finished", "report" => report})
       when is_map(report) do
    agent = Map.get(delivery, :implementer) || "codex"
    model = step_model(step, "implementer", agent, delivery.project_id)
    steps_md = format_bullets("Planned steps", report["steps"])
    criteria_md = format_bullets("Acceptance criteria", report["acceptance"])

    clarification =
      if is_binary(report["clarification"]) and report["clarification"] != "",
        do: "\n\nClarification requested: #{report["clarification"]}",
        else: ""

    %{
      author_role: "implementer",
      agent_id: agent,
      model_id: model,
      kind: "stage_log",
      summary: sanitize_line("Plan prepared: #{report["summary"]}", @max_summary),
      body:
        sanitize_text(
          Enum.join(
            Enum.reject([report["summary"], steps_md, criteria_md], &(&1 in [nil, ""])),
            "\n\n"
          ) <>
            clarification,
          @max_body
        )
    }
  end

  defp step_entry(delivery, %{kind: "implement"} = step, %{"status" => "finished"} = receipt) do
    agent = Map.get(delivery, :implementer) || "codex"
    model = step_model(step, "implementer", agent, delivery.project_id)
    sha = String.slice(to_string(receipt["head_commit"] || ""), 0, 12)

    %{
      author_role: "implementer",
      agent_id: agent,
      model_id: model,
      kind: "stage_log",
      summary:
        sanitize_line(
          "Cycle #{step.cycle} implementation completed#{if sha != "", do: " (#{sha})", else: ""}",
          @max_summary
        ),
      body:
        sanitize_text(
          "Candidate head commit: #{receipt["head_commit"] || "recorded"}",
          @max_body
        )
    }
  end

  defp step_entry(delivery, %{kind: kind} = step, %{"status" => "finished", "report" => report})
       when kind in ["review", "merge_review"] and is_map(report) do
    agent = delivery.reviewer || "codex"
    model = step_model(step, "reviewer", agent, delivery.project_id)
    verdict = report["verdict"] || "reviewed"

    verdict_label =
      case verdict do
        "approved" -> "Approved"
        "changes_requested" -> "Changes requested"
        "needs_spec_revision" -> "Needs spec clarification"
        other -> other
      end

    issues =
      case report["issues"] do
        list when is_list(list) and list != [] ->
          items = Enum.map(list, fn i -> "- [#{i["criterion"]}] #{i["message"]}" end)
          "Issues:\n" <> Enum.join(items, "\n")

        _ ->
          ""
      end

    %{
      author_role: "reviewer",
      agent_id: agent,
      model_id: model,
      kind: "comment",
      summary: sanitize_line("#{verdict_label}: #{report["summary"]}", @max_summary),
      body:
        sanitize_text(
          Enum.join(Enum.reject([report["summary"], issues], &(&1 == "")), "\n\n"),
          @max_body
        )
    }
  end

  defp step_entry(delivery, %{kind: "resolve"} = step, %{
         "status" => "finished",
         "report" => report
       })
       when is_map(report) do
    agent = Map.get(delivery, :analytic) || "codex"
    model = step_model(step, "analytic", agent, delivery.project_id)
    steps_md = format_bullets("Resolution steps", report["steps"])
    assumptions_md = format_bullets("Assumptions", report["assumptions"])

    %{
      author_role: "analytic",
      agent_id: agent,
      model_id: model,
      kind: "comment",
      summary: sanitize_line("Analytic diagnosis: #{report["summary"]}", @max_summary),
      body:
        sanitize_text(
          Enum.join(
            Enum.reject([report["summary"], steps_md, assumptions_md], &(&1 in [nil, ""])),
            "\n\n"
          ),
          @max_body
        )
    }
  end

  defp step_entry(_delivery, %{kind: "publish"}, %{"status" => "finished"} = receipt) do
    sha = String.slice(to_string(receipt["candidate_commit"] || ""), 0, 12)

    %{
      author_role: "system",
      agent_id: nil,
      model_id: nil,
      kind: "stage_log",
      summary: sanitize_line("Integrated commit #{sha} into target branch", @max_summary),
      body: sanitize_text("Published commit: #{receipt["candidate_commit"]}", @max_body)
    }
  end

  defp step_entry(delivery, step, %{"status" => status} = receipt)
       when status in ["failed", "interrupted"] and
              step.kind in [
                "plan",
                "implement",
                "check",
                "review",
                "merge_review",
                "resolve",
                "post_check"
              ] do
    {role, agent} =
      case step.kind do
        k when k in ["review", "merge_review"] -> {"reviewer", delivery.reviewer}
        "resolve" -> {"analytic", Map.get(delivery, :analytic)}
        k when k in ["plan", "implement"] -> {"implementer", Map.get(delivery, :implementer)}
        _ -> {"system", nil}
      end

    model = if agent, do: step_model(step, role, agent, delivery.project_id)
    reason = receipt["reason"] || receipt["outcome"] || status

    %{
      author_role: role,
      agent_id: agent,
      model_id: model,
      kind: "stage_log",
      summary: sanitize_line("Stage #{step.kind} #{status}: #{reason}", @max_summary),
      body: sanitize_text(to_string(reason), @max_body)
    }
  end

  defp step_entry(_, _, _), do: nil

  defp step_model(step, role_kind, agent_id, project_id) do
    case get_in(step.input || %{}, ["model_profile", "model"]) do
      m when is_binary(m) and m != "" ->
        m

      _ ->
        Roles.selection_for(role_kind, agent_id, project_id).model_id
    end
  end

  defp format_bullets(_heading, list) when not is_list(list) or list == [], do: ""

  defp format_bullets(heading, list) do
    lines = Enum.map(list, &"- #{&1}")
    "#{heading}:\n" <> Enum.join(lines, "\n")
  end

  def present(%Entry{} = e) do
    tag =
      cond do
        e.author_role in ~w(reviewer implementer analytic) and is_binary(e.agent_id) ->
          Roles.binding_tag(e.author_role, e.agent_id, e.model_id, nil)

        e.author_role == "owner" ->
          "Owner"

        true ->
          "BOSS"
      end

    %{
      id: e.id,
      project_id: e.project_id,
      task_id: e.task_id,
      delivery_id: e.delivery_id,
      spec_revision_id: e.spec_revision_id,
      author_role: e.author_role,
      agent_id: e.agent_id,
      model_id: e.model_id,
      author_tag: tag,
      kind: e.kind,
      cycle: e.cycle,
      stage: e.stage,
      summary: e.summary,
      body: e.body,
      inserted_at: e.inserted_at
    }
  end

  defp sanitize_line(text, limit) when is_binary(text) do
    text
    |> String.replace(~r/[\x00-\x1F\x7F]+/u, " ")
    |> String.trim()
    |> clip_utf8(limit)
  end

  defp sanitize_text(text, limit) when is_binary(text) do
    text
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u, "")
    |> String.trim()
    |> clip_utf8(limit)
  end

  defp clip_utf8(text, max_bytes) when byte_size(text) <= max_bytes, do: text

  defp clip_utf8(text, max_bytes) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({"", 0}, fn g, {acc, used} ->
      sz = byte_size(g)
      if used + sz <= max_bytes, do: {:cont, {acc <> g, used + sz}}, else: {:halt, {acc, used}}
    end)
    |> elem(0)
    |> String.trim_trailing()
  end
end
