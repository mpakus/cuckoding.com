#!/usr/bin/ruby
# frozen_string_literal: true

# Protocol fixture, never a provider integration or acceptance substitute.
require 'json'
STDOUT.sync = true
scenario = ARGV.include?('acp') ? 'cursor-model' : ARGV.fetch(0, 'success')
request_log = File.open('acp-requests.jsonl', 'w')
request_log.sync = true
session = 'fixture-session'
prompt_id = nil
permission_requested = false

def reply(id, result)
  puts JSON.generate(jsonrpc: '2.0', id: id, result: result)
end

def update(session, fields)
  puts JSON.generate(jsonrpc: '2.0', method: 'session/update', params: {sessionId: session, update: fields})
end

configuration = {
  modes: {currentModeId: 'default', availableModes: %w[read-only workspace-write plan agent dontAsk].map { |id| {id: id, name: id} }},
  models: {currentModelId: scenario == 'model-unreported' ? 'default' : 'fixture-model', availableModels: [{modelId: 'fixture-model', name: 'Fixture'}]}
}
if %w[modern config-drift cursor-model].include?(scenario)
  configuration.delete(:models)
  configuration[:configOptions] = [
    {id: 'mode', category: 'mode', type: 'select', currentValue: 'read-only', options: [{value: 'read-only', name: 'Read only'}]},
    {id: 'provider-model', category: 'model', type: 'select', currentValue: 'default', options: [{value: 'fixture-model', name: 'Fixture'}]}
  ]
  if scenario == 'cursor-model'
    abort 'Missing saved CLI model' unless ARGV[ARGV.index('--model') + 1] == 'fixture-model'
    configuration[:configOptions][0][:currentValue] = 'plan'
    configuration[:configOptions][1][:currentValue] = 'fixture[effort=high]'
    configuration[:configOptions][1][:options] = [{value: 'fixture[effort=high]', name: 'Fixture'}]
  end
end

while line = STDIN.gets
  message = JSON.parse(line)
  request_log.puts(JSON.generate(message))
  id = message['id']
  case message['method']
  when 'initialize'
    next if scenario == 'wait-initialize'
    reply(id, protocolVersion: scenario == 'wrong-version' ? 99 : 1,
          agentCapabilities: {loadSession: scenario != 'no-load'})
  when 'session/new', 'session/load'
    if message['method'] == 'session/load'
      session = message['params'].fetch('sessionId')
      update(session, sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: 'historical-message'})
      update(session, sessionUpdate: 'usage_update', used: 900, size: 1000)
    end
    reply(id, configuration.merge(sessionId: session))
  when 'session/set_mode'
    update(session, sessionUpdate: 'current_mode_update', currentModeId: message['params']['modeId'])
    reply(id, {})
  when 'session/set_model'
    reply(id, {})
  when 'session/set_config_option'
    option = configuration.fetch(:configOptions).find { |entry| entry[:id] == message['params']['configId'] }
    option[:currentValue] = message['params']['value']
    update(session, sessionUpdate: 'config_option_update', configOptions: configuration[:configOptions])
    reply(id, configOptions: configuration[:configOptions])
  when 'session/prompt'
    prompt_id = id
    case scenario
    when 'permission'
      puts JSON.generate(jsonrpc: '2.0', id: 'permission', method: 'session/request_permission',
                         params: {sessionId: session, toolCall: {kind: 'execute', title: 'fixture-secret-canary command', rawInput: 'must-not-persist'}, options: []})
      permission_requested = true
    when 'wrong-session'
      update('other-session', sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: 'forged'})
    when 'malformed'
      puts 'not JSON'
    when 'partial'
      STDOUT.write('{"jsonrpc":')
      exit 0
    when 'wait', 'ignore-cancel'
      update(session, sessionUpdate: 'tool_call', toolCallId: 'tool-1', status: 'in_progress')
    when 'config-drift'
      configuration[:configOptions][0][:currentValue] = 'bypassPermissions'
      update(session, sessionUpdate: 'config_option_update', configOptions: configuration[:configOptions])
    else
      STDERR.write("fixture-secret-canary\n")
      update(session, sessionUpdate: 'agent_thought_chunk', content: {type: 'text', text: 'private-reasoning-canary'})
      update(session, sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: 'fixture-secret-'})
      update(session, sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: 'canary'})
      update(session, sessionUpdate: 'tool_call', toolCallId: 'tool-1', status: 'in_progress', rawInput: 'private-tool-canary')
      sleep 0.1
      update(session, sessionUpdate: 'tool_call_update', toolCallId: 'tool-1', status: 'completed')
      update(session, sessionUpdate: 'usage_update', used: 500, size: 1000)
      update(session, sessionUpdate: 'usage_update', used: 500, size: 1000)
      update(session, sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: 'A preliminary message'}) if scenario == 'modern'
      update(session, sessionUpdate: 'agent_message_chunk', messageId: scenario == 'modern' ? 'structured-result' : nil, content: {type: 'text', text: '{"summary":"done"}'})
      reply(id, stopReason: 'end_turn', usage: {inputTokens: 5, outputTokens: 3, cachedReadTokens: 2})
      reply(id, stopReason: 'end_turn') if scenario == 'duplicate'
    end
  when 'session/cancel'
    unless scenario == 'ignore-cancel'
      reply(prompt_id, stopReason: 'cancelled')
    end
  else
    if permission_requested && message['id'] == 'permission'
      abort 'Client expanded permission' unless message.dig('result', 'outcome', 'outcome') == 'cancelled'
    end
  end
end

sleep 60 if scenario == 'ignore-eof'
