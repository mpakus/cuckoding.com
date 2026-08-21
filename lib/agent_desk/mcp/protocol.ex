defmodule AgentDesk.MCP.Protocol do
  @moduledoc """
  MCP JSON-RPC methods for the internal Agent Hub. Identity comes from the token.
  """

  alias AgentDesk.A2A
  alias AgentDesk.Agents.Session
  alias AgentDesk.Ids
  alias AgentDesk.Projects
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope

  @tools [
    "hub_register",
    "hub_heartbeat",
    "hub_update_status",
    "hub_list_agents",
    "hub_get_agent_card",
    "hub_find_agents",
    "hub_list_tasks",
    "hub_get_task",
    "hub_create_task",
    "hub_delegate_task",
    "hub_list_delegations",
    "hub_accept_delegation",
    "hub_reject_delegation",
    "hub_revoke_delegation",
    "hub_redirect_delegation",
    "hub_update_task",
    "hub_cancel_task",
    "hub_complete_task",
    "hub_subscribe_task",
    "hub_claim_resources",
    "hub_release_resources",
    "hub_renew_resources",
    "hub_list_resources",
    "hub_send_message",
    "hub_broadcast",
    "hub_ack_message",
    "hub_list_inbox",
    "hub_publish_artifact",
    "hub_get_artifact",
    "hub_publish_handoff",
    "hub_accept_handoff",
    "hub_request_review"
  ]

  @spec handle(Session.t(), map()) :: {:ok, map()} | {:error, map()}
  def handle(%Session{} = session, %{"method" => method} = msg) do
    id = Map.get(msg, "id")
    params = Map.get(msg, "params", %{})

    case dispatch(session, method, params) do
      {:ok, result} -> {:ok, %{"jsonrpc" => "2.0", "id" => id, "result" => result}}
      {:error, reason} -> {:error, error_payload(id, reason)}
    end
  end

  defp dispatch(_session, "initialize", _params) do
    {:ok,
     %{
       "protocolVersion" => "2024-11-05",
       "serverInfo" => %{"name" => "agentdesk-hub", "version" => "0.1.0"},
       "capabilities" => %{"tools" => %{}}
     }}
  end

  defp dispatch(_session, "notifications/initialized", _params), do: {:ok, %{}}

  defp dispatch(_session, "tools/list", _params) do
    tools =
      Enum.map(@tools, fn name ->
        %{"name" => name, "description" => name, "inputSchema" => %{"type" => "object"}}
      end)

    {:ok, %{"tools" => tools}}
  end

  defp dispatch(session, "tools/call", params) do
    name = params["name"]
    args = params["arguments"] || %{}
    call_tool(session, name, args)
  end

  defp dispatch(session, name, params) when name in @tools, do: call_tool(session, name, params)
  defp dispatch(_session, _name, _params), do: {:error, :unknown_method}

  defp call_tool(session, name, args) do
    with {:ok, project} <- Projects.get_project(session.project_id) do
      scope = Scope.for_agent(project, session)
      tool(scope, name, args)
    end
  end

  defp tool(scope, "hub_register", args) do
    A2A.register_card(scope, %{
      name: args["name"] || scope.agent_session.display_name,
      description: args["description"] || "",
      skills: args["skills"] || [],
      availability: "idle"
    })
    |> wrap_card()
  end

  defp tool(scope, "hub_heartbeat", args) do
    with {:ok, _} <- A2A.heartbeat(scope, %{status: args["status"]}) do
      lease_ids = args["lease_ids"] || []
      _ = if lease_ids != [], do: Manager.renew(scope, lease_ids)
      {:ok, %{"ok" => true, "agents" => A2A.list_agents(scope)}}
    end
  end

  defp tool(scope, "hub_update_status", args) do
    A2A.heartbeat(scope, %{status: args["status"]})
    {:ok, %{"ok" => true}}
  end

  defp tool(scope, "hub_list_agents", _args), do: {:ok, %{"agents" => A2A.list_agents(scope)}}

  defp tool(scope, "hub_get_agent_card", args) do
    wrap(A2A.get_agent(scope, args["agent_id"]))
  end

  defp tool(scope, "hub_find_agents", args) do
    {:ok,
     %{
       "agents" =>
         A2A.find_agents(scope, skill: args["skill"], availability: args["availability"])
     }}
  end

  defp tool(scope, "hub_delegate_task", args) do
    wrap(
      A2A.propose_delegation(scope, %{
        task_id: args["task_id"],
        to_agent_id: args["recipient_agent_id"],
        reason: args["description"] || args["title"] || "delegate",
        idempotency_key: args["idempotency_key"] || Ids.generate()
      })
    )
  end

  defp tool(scope, "hub_accept_delegation", args) do
    wrap(
      A2A.accept_delegation(scope, args["delegation_id"], %{
        idempotency_key: args["idempotency_key"],
        expected_version: args["expected_version"] || 1
      })
    )
  end

  defp tool(scope, "hub_reject_delegation", args) do
    wrap(
      A2A.reject_delegation(scope, args["delegation_id"], %{
        idempotency_key: args["idempotency_key"],
        expected_version: args["expected_version"] || 1,
        response_reason: args["reason"]
      })
    )
  end

  defp tool(scope, "hub_revoke_delegation", args) do
    wrap(
      A2A.revoke_delegation(scope, args["delegation_id"], %{
        idempotency_key: args["idempotency_key"]
      })
    )
  end

  defp tool(scope, "hub_redirect_delegation", args) do
    wrap(
      A2A.redirect_delegation(scope, args["delegation_id"], %{
        idempotency_key: args["idempotency_key"],
        to_agent_id: args["to_agent_id"]
      })
    )
  end

  defp tool(scope, "hub_send_message", args) do
    wrap(
      A2A.send_message(scope, %{
        idempotency_key: args["idempotency_key"],
        context_id: args["context_id"],
        scope: args["scope"] || "direct",
        recipient_agent_id: args["recipient_agent_id"],
        task_id: args["task_id"],
        body: args["body"],
        parts: args["parts"],
        kind: args["kind"] || "info"
      })
    )
  end

  defp tool(scope, "hub_broadcast", args) do
    wrap(A2A.broadcast(scope, Map.merge(atomize_limited(args), %{scope: "project"})))
  end

  defp tool(scope, "hub_ack_message", args) do
    wrap(A2A.acknowledge(scope, args["delivery_id"]))
  end

  defp tool(scope, "hub_list_inbox", args) do
    cursor = args["cursor"] || 0
    {:ok, %{"deliveries" => Enum.map(A2A.inbox(scope, cursor), &delivery_map/1)}}
  end

  defp tool(scope, "hub_claim_resources", args) do
    resources = args["resources"] || []
    opts = [reason: args["reason"] || "claim", ttl_seconds: args["ttl_seconds"] || 300]

    case Manager.claim(scope, resources, opts) do
      {:ok, leases} -> {:ok, %{"granted" => true, "leases" => Enum.map(leases, &lease_map/1)}}
      {:error, {:conflict, conflicts}} -> {:ok, %{"granted" => false, "conflicts" => conflicts}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp tool(scope, "hub_release_resources", args) do
    wrap(Manager.release(scope, args["lease_ids"] || []))
  end

  defp tool(scope, "hub_renew_resources", args) do
    wrap(Manager.renew(scope, args["lease_ids"] || []))
  end

  defp tool(scope, "hub_list_resources", _args) do
    {:ok, %{"leases" => Enum.map(Manager.list_project(scope.project.id), &lease_map/1)}}
  end

  defp tool(scope, "hub_get_artifact", args) do
    wrap(A2A.get_artifact(scope, args["artifact_id"]))
  end

  defp tool(scope, "hub_publish_artifact", args) do
    wrap(
      A2A.publish_artifact(scope, %{
        context_id: args["context_id"],
        task_id: args["task_id"],
        kind: args["kind"] || "other",
        name: args["name"],
        mime_type: args["mime_type"] || "application/octet-stream",
        path: args["path"],
        sha256: args["sha256"],
        size_bytes: args["size_bytes"] || 0
      })
    )
  end

  defp tool(scope, "hub_subscribe_task", args) do
    :ok = A2A.subscribe_task(scope, args["task_id"])
    {:ok, %{"ok" => true}}
  end

  defp tool(scope, "hub_list_tasks", _args) do
    {:ok, %{"tasks" => Enum.map(A2A.list_tasks(scope), &encode/1)}}
  end

  defp tool(scope, "hub_get_task", args) do
    case Enum.find(A2A.list_tasks(scope), &(&1.id == args["task_id"])) do
      nil -> {:error, :not_found}
      task -> {:ok, encode(task)}
    end
  end

  defp tool(scope, "hub_list_delegations", _args) do
    {:ok, %{"delegations" => Enum.map(A2A.list_delegations(scope), &encode/1)}}
  end

  defp tool(scope, "hub_update_task", args) do
    case listed_task(scope, args["task_id"]) do
      nil ->
        {:error, :not_found}

      task ->
        wrap(
          A2A.update_task(scope, task, %{
            status: args["status"],
            expected_version: args["expected_version"]
          })
        )
    end
  end

  defp tool(scope, "hub_cancel_task", args) do
    case listed_task(scope, args["task_id"]) do
      nil -> {:error, :not_found}
      task -> wrap(A2A.update_task(scope, task, %{status: "cancelled"}))
    end
  end

  defp tool(scope, "hub_complete_task", args) do
    case listed_task(scope, args["task_id"]) do
      nil -> {:error, :not_found}
      task -> wrap(A2A.update_task(scope, task, %{status: "completed"}))
    end
  end

  defp tool(scope, "hub_create_task", args) do
    with {:ok, context} <- fetch_context(scope, args["context_id"]) do
      wrap(
        A2A.create_task(scope, context, %{title: args["title"], description: args["description"]})
      )
    end
  end

  defp tool(scope, "hub_publish_handoff", args) do
    wrap(AgentDesk.Worktrees.Handoffs.publish(scope, args))
  end

  defp tool(scope, "hub_accept_handoff", args) do
    wrap(AgentDesk.Worktrees.Handoffs.accept(scope, args["artifact_id"]))
  end

  defp tool(scope, "hub_request_review", args) do
    wrap(
      A2A.propose_delegation(scope, %{
        task_id: args["task_id"],
        to_agent_id: args["recipient_agent_id"],
        reason: args["reason"] || "Please review",
        idempotency_key: args["idempotency_key"] || Ids.generate()
      })
    )
  end

  defp tool(_scope, _name, _args), do: {:error, :unknown_method}

  defp listed_task(scope, id) do
    Enum.find(A2A.list_tasks(scope), &(&1.id == id))
  end

  defp fetch_context(scope, id) do
    case AgentDesk.Repo.get_by(AgentDesk.A2A.Context, id: id, project_id: scope.project.id) do
      nil -> {:error, :not_found}
      context -> {:ok, context}
    end
  end

  defp wrap({:ok, value}), do: {:ok, encode(value)}
  defp wrap({:error, reason}), do: {:error, reason}

  defp wrap_card(result), do: wrap(result)

  defp encode(%{id: id} = struct),
    do: %{"id" => id, "type" => struct.__struct__ |> Module.split() |> List.last()}

  defp encode(map) when is_map(map), do: map
  defp encode(list) when is_list(list), do: Enum.map(list, &encode/1)
  defp encode(other), do: %{"value" => inspect(other)}

  defp lease_map(lease) do
    %{
      "id" => lease.id,
      "type" => lease.resource_type,
      "key" => lease.resource_key,
      "mode" => lease.mode,
      "expires_at" => DateTime.to_iso8601(lease.expires_at)
    }
  end

  defp delivery_map(delivery) do
    %{"id" => delivery.id, "inbox_sequence" => delivery.inbox_sequence, "state" => delivery.state}
  end

  defp atomize_limited(args) do
    %{
      idempotency_key: args["idempotency_key"],
      context_id: args["context_id"],
      body: args["body"],
      parts: args["parts"],
      kind: args["kind"] || "coordination"
    }
  end

  defp error_payload(id, reason) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => -32_000, "message" => inspect(reason)}
    }
  end
end
