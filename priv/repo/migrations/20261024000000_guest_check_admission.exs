defmodule Cuckoding.Repo.Migrations.GuestCheckAdmission do
  use Ecto.Migration
  def up do
    # The additive version also fences older bundles from new check grants.
    execute """
    CREATE INDEX battle_attempts_check_images
    ON battle_attempts(json_extract(result, '$.check_image.spec_sha256'), json_extract(result, '$.check_image.key'), inserted_at, id)
    WHERE stage = 'admission' AND state = 'completed'
    """
    execute """
    CREATE INDEX battle_attempts_guest_reservations
    ON battle_attempts(state, stage)
    WHERE json_extract(request, '$.snapshot.check_execution.version') = 'isolated-guest-checks-v1'
      AND coalesce(json_extract(result, '$.cleanup_verified'), 0) != 1
    """
  end
  def down, do: raise("forward-only migration; restore a verified backup")
end
