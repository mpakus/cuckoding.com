defmodule AgentDesk.Repo.Migrations.CreateA2AFoundation do
  use Ecto.Migration

  def change do
    create table(:agent_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider, :text, null: false
      add :display_name, :text, null: false
      add :role, :text
      add :status, :text, null: false
      add :provider_session_id, :text
      add :provider_version, :text
      add :process_identity, :map, null: false, default: %{}
      add :capability_hash, :text
      add :capability_expires_at, :utc_datetime_usec
      add :last_heartbeat_at, :utc_datetime_usec
      add :started_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      add :exit_reason, :text
      add :settings, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_sessions, [:project_id, :status])
    create index(:agent_sessions, [:provider, :provider_session_id])

    create table(:agent_cards, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :delete_all), null: false

      add :revision, :integer, null: false, default: 1
      add :name, :text, null: false
      add :description, :text, null: false
      add :skills, {:array, :map}, null: false, default: []
      add :input_modes, {:array, :string}, null: false, default: []
      add :output_modes, {:array, :string}, null: false, default: []
      add :features, :map, null: false, default: %{}
      add :availability, :text, null: false
      add :published_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_cards, [:agent_session_id])
    create index(:agent_cards, [:project_id, :availability])
    create index(:agent_cards, [:project_id, :updated_at])

    create table(:a2a_contexts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :title, :text, null: false
      add :status, :text, null: false
      add :created_by_type, :text, null: false

      add :created_by_agent_id,
          references(:agent_sessions, type: :binary_id, on_delete: :nilify_all)

      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:a2a_contexts, [:project_id, :status, :updated_at])

    create table(:a2a_context_participants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :context_id, references(:a2a_contexts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :delete_all), null: false

      add :role, :text, null: false
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:a2a_context_participants, [:context_id, :agent_session_id],
             name: :a2a_context_participants_active_index,
             where: "left_at IS NULL"
           )

    create index(:a2a_context_participants, [:agent_session_id, :left_at])

    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :context_id, references(:a2a_contexts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :parent_task_id, references(:tasks, type: :binary_id, on_delete: :nilify_all)
      add :title, :text, null: false
      add :description, :text, null: false, default: ""
      add :status, :text, null: false
      add :status_reason, :text
      add :lock_version, :integer, null: false, default: 1
      add :priority, :integer, null: false, default: 0

      add :assigned_agent_id,
          references(:agent_sessions, type: :binary_id, on_delete: :nilify_all)

      add :created_by, :text, null: false
      add :metadata, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tasks, [:project_id, :status, :priority])
    create index(:tasks, [:context_id, :status, :priority])
    create index(:tasks, [:assigned_agent_id, :status])
    create index(:tasks, [:parent_task_id])

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :context_id, references(:a2a_contexts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :task_id, references(:tasks, type: :binary_id, on_delete: :nilify_all)
      add :sender_agent_id, references(:agent_sessions, type: :binary_id, on_delete: :nilify_all)

      add :recipient_agent_id,
          references(:agent_sessions, type: :binary_id, on_delete: :nilify_all)

      add :scope, :text, null: false
      add :kind, :text, null: false
      add :body, :text
      add :parts, {:array, :map}, null: false, default: []
      add :priority, :text, null: false, default: "normal"
      add :requires_ack, :boolean, null: false, default: true
      add :metadata, :map, null: false, default: %{}
      add :idempotency_key, :text, null: false
      add :correlation_id, :binary_id, null: false
      add :causation_id, :binary_id
      add :reply_to_message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:messages, [:project_id, :inserted_at])
    create index(:messages, [:context_id, :inserted_at])
    create index(:messages, [:recipient_agent_id, :inserted_at])
    create index(:messages, [:task_id, :inserted_at])
    create index(:messages, [:correlation_id])

    create unique_index(:messages, [:sender_agent_id, :idempotency_key],
             name: :messages_sender_idempotency_index
           )

    create table(:message_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :delete_all), null: false

      add :inbox_sequence, :integer, null: false
      add :state, :text, null: false
      add :attempt_count, :integer, null: false, default: 0
      add :last_error, :text
      add :injected_at, :utc_datetime_usec
      add :acknowledged_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:message_deliveries, [:message_id, :agent_session_id])
    create unique_index(:message_deliveries, [:agent_session_id, :inbox_sequence])
    create index(:message_deliveries, [:agent_session_id, :state, :inbox_sequence])

    create table(:task_delegations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :context_id, references(:a2a_contexts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false
      add :from_agent_id, references(:agent_sessions, type: :binary_id, on_delete: :nilify_all)

      add :to_agent_id, references(:agent_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :text, null: false
      add :reason, :text, null: false
      add :response_reason, :text
      add :request_message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :response_message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :idempotency_key, :text, null: false
      add :lock_version, :integer, null: false, default: 1
      add :expires_at, :utc_datetime_usec
      add :responded_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:task_delegations, [:from_agent_id, :idempotency_key],
             name: :task_delegations_idempotency_index
           )

    create index(:task_delegations, [:to_agent_id, :status, :inserted_at])
    create index(:task_delegations, [:task_id, :status])
    create index(:task_delegations, [:status, :expires_at])

    create table(:idempotency_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :delete_all), null: false

      add :idempotency_key, :text, null: false
      add :operation, :text, null: false
      add :request_hash, :text, null: false
      add :result_status, :text, null: false
      add :result_payload, :map, null: false, default: %{}
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:idempotency_records, [:agent_session_id, :idempotency_key])
    create index(:idempotency_records, [:expires_at])

    create table(:artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :context_id, references(:a2a_contexts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :task_id, references(:tasks, type: :binary_id, on_delete: :nilify_all)
      add :agent_session_id, references(:agent_sessions, type: :binary_id, on_delete: :nilify_all)
      add :kind, :text, null: false
      add :name, :text, null: false
      add :mime_type, :text, null: false
      add :path, :text, null: false
      add :sha256, :text, null: false
      add :size_bytes, :integer, null: false
      add :state, :text, null: false
      add :revision_of_id, references(:artifacts, type: :binary_id, on_delete: :nilify_all)
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:artifacts, [:project_id, :kind, :inserted_at])
    create index(:artifacts, [:context_id, :inserted_at])
    create index(:artifacts, [:task_id])
    create index(:artifacts, [:sha256])
  end
end
