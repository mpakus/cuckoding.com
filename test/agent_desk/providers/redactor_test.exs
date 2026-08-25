defmodule AgentDesk.Providers.RedactorTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.Redactor

  test "redacts complete authorization and credential header values" do
    text =
      Redactor.redact("""
      AUTHORIZATION: bEaReR prefix.abcdefghijklmnopqrstuvwxyz0123456789.suffix
      Proxy-Authorization: BASIC dXNlcjpwYXNzd29yZA==
      X-API-Key: header-api-key-value-with-a-long-suffix
      Content-Type: application/json
      """)

    refute text =~ "prefix."
    refute text =~ ".suffix"
    refute text =~ "dXNlcjpwYXNzd29yZA"
    refute text =~ "long-suffix"
    assert text =~ "AUTHORIZATION: [REDACTED]"
    assert text =~ "Proxy-Authorization: [REDACTED]"
    assert text =~ "X-API-Key: [REDACTED]"
    assert text =~ "Content-Type: application/json"
  end

  test "redacts folded authorization values without leaking later chunks" do
    text =
      Redactor.redact(
        "Authorization: Bearer first-long-token-chunk\r\n" <>
          "  second-long-token-chunk\r\n" <>
          "\tfinal-long-token-suffix\r\n" <>
          "Accept: application/json"
      )

    refute text =~ "first-long-token-chunk"
    refute text =~ "second-long-token-chunk"
    refute text =~ "final-long-token-suffix"
    assert text == "Authorization: [REDACTED]\r\nAccept: application/json"
  end

  test "redacts sensitive map and header-list values by case-insensitive key" do
    payload = %{
      "Authorization" => "Bearer map-token-with-suffix",
      :api_key => "map-api-key-with-suffix",
      "nested" => [
        %{"ToKeN" => "nested-token-with-suffix"},
        {"X-Auth-Token", "header-list-token-with-suffix"}
      ],
      "message" => "Keep this ordinary prose."
    }

    assert Redactor.redact(payload) == %{
             "Authorization" => "[REDACTED]",
             :api_key => "[REDACTED]",
             "nested" => [
               %{"ToKeN" => "[REDACTED]"},
               {"X-Auth-Token", "[REDACTED]"}
             ],
             "message" => "Keep this ordinary prose."
           }
  end

  test "redacts arbitrary credential suffixes in structured values" do
    payload = %{
      "AGENTDESK_CAPABILITY_TOKEN" => "capability-value-and-suffix",
      "VENDOR_API_KEY" => "vendor-api-key-and-suffix",
      "service_secret" => "service-secret-and-suffix",
      :database_password => "database-password-and-suffix",
      "HTTP_AUTHORIZATION" => "Bearer structured-authorization-value",
      "token_count" => 14,
      "message" => "Keep the API key rotation guidance and token count."
    }

    redacted = Redactor.redact(payload)

    assert redacted["AGENTDESK_CAPABILITY_TOKEN"] == "[REDACTED]"
    assert redacted["VENDOR_API_KEY"] == "[REDACTED]"
    assert redacted["service_secret"] == "[REDACTED]"
    assert redacted[:database_password] == "[REDACTED]"
    assert redacted["HTTP_AUTHORIZATION"] == "[REDACTED]"
    assert redacted["token_count"] == 14
    assert redacted["message"] == "Keep the API key rotation guidance and token count."
  end

  test "redacts complete dotenv and structured assignment values" do
    text =
      Redactor.redact("""
      AGENTDESK_CAPABILITY_TOKEN=capability-token-value.with-a-suffix
      export SERVICE_API_KEY="quoted api key with a suffix"
      vendor_secret='single quoted secret with suffix'
      database_password: yaml-password-value with suffix
      HTTP_AUTHORIZATION=Bearer environment-authorization-value
      STATUS_MESSAGE=Useful nonsecret prose remains.
      """)

    refute text =~ "capability-token-value"
    refute text =~ "quoted api key"
    refute text =~ "single quoted secret"
    refute text =~ "yaml-password"
    refute text =~ "environment-authorization"
    assert text =~ "AGENTDESK_CAPABILITY_TOKEN=[REDACTED]"
    assert text =~ "SERVICE_API_KEY=[REDACTED]"
    assert text =~ "vendor_secret=[REDACTED]"
    assert text =~ "database_password: [REDACTED]"
    assert text =~ "STATUS_MESSAGE=Useful nonsecret prose remains."
  end

  test "redacts authorization assignment and quoted header variants" do
    text =
      Redactor.redact("""
      Proxy_Authorization = Basic proxy-credential-with-suffix
      curl -H 'Authorization: Bearer inline-credential-with-suffix' https://example.test
      authorization policy remains useful prose
      """)

    refute text =~ "proxy-credential"
    refute text =~ "inline-credential"
    assert text =~ "Proxy_Authorization = [REDACTED]"
    assert text =~ "Authorization: [REDACTED]' https://example.test"
    assert text =~ "authorization policy remains useful prose"
  end

  test "redacts JSON and query-like credential values completely" do
    json =
      ~s({"authorization":"Bearer json-token.with.a-long-suffix","api_key":"json-key-with suffix","note":"token handling is ordinary prose"})

    query =
      "https://example.test/callback?access_token=query-token-with-a-long-suffix" <>
        "&api-key=\"quoted-key with a suffix\"&q=token+handling"

    redacted_json = Redactor.redact(json)
    redacted_query = Redactor.redact(query)

    refute redacted_json =~ "json-token"
    refute redacted_json =~ "with suffix"
    assert redacted_json =~ ~s("authorization":"[REDACTED]")
    assert redacted_json =~ ~s("api_key":"[REDACTED]")
    assert redacted_json =~ "token handling is ordinary prose"

    refute redacted_query =~ "query-token"
    refute redacted_query =~ "quoted-key"
    refute redacted_query =~ "a suffix"
    assert redacted_query =~ "access_token=[REDACTED]"
    assert redacted_query =~ ~s(api-key="[REDACTED]")
    assert redacted_query =~ "q=token+handling"
  end

  test "redacts database URL credentials while preserving connection location" do
    text =
      Redactor.redact(
        "primary=postgresql://db_user:db-password-with-suffix@db.internal:5432/app " <>
          "cache=rediss://cache-user:cache-secret-with-suffix@cache.internal/0"
      )

    refute text =~ "db_user"
    refute text =~ "db-password"
    refute text =~ "cache-user"
    refute text =~ "cache-secret"
    assert text =~ "postgresql://[REDACTED]@db.internal:5432/app"
    assert text =~ "rediss://[REDACTED]@cache.internal/0"
  end

  test "redacts PEM private key bodies completely" do
    text =
      Redactor.redact("""
      key follows
      -----BEGIN OPENSSH PRIVATE KEY-----
      b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ==
      another-private-key-line-that-must-not-remain
      -----END OPENSSH PRIVATE KEY-----
      certificate metadata remains
      """)

    refute text =~ "b3BlbnNzaC"
    refute text =~ "another-private-key-line"
    assert text =~ "-----BEGIN OPENSSH PRIVATE KEY-----\n[REDACTED]\n"
    assert text =~ "-----END OPENSSH PRIVATE KEY-----"
    assert text =~ "certificate metadata remains"
  end

  test "redacts known provider token shapes without leaving suffixes" do
    text =
      Redactor.redact(
        "keys sk-abcdefghijklmnopqrstuvwxyz0123456789 " <>
          "gho_abcdefghijklmnopqrstuvwxyz0123456789 " <>
          "xoxb-REDACTED-TEST-TOKEN"
      )

    refute text =~ "abcdefghijklmnopqrstuvwxyz"
    assert text == "keys [REDACTED] [REDACTED] [REDACTED]"
  end

  test "does not corrupt ordinary prose containing credential words" do
    prose =
      "Token: a lexical unit. The bearer of good news described basic authentication, " <>
        "API key rotation, and authorization policy."

    assert Redactor.redact(prose) == prose
  end
end
