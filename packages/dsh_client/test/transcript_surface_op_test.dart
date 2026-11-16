import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

void main() {
  test('a replace surface op drops the covered transcript events', () {
    final transcript = ChatTranscript();
    transcript.apply(
      ToolCallEvent(
        1,
        DateTime.fromMillisecondsSinceEpoch(1),
        const {},
        turn: 1,
        step: 1,
        callId: 'call-1',
        name: 'ui_render',
        arguments: '{}',
      ),
    );
    transcript.apply(
      ToolResultEvent(
        2,
        DateTime.fromMillisecondsSinceEpoch(2),
        const {},
        turn: 1,
        step: 1,
        message: const Message(
          id: 'message-1',
          role: MessageRole.tool,
          parts: [],
          source: MessageSource('tool', {}),
          toolCallId: 'call-1',
        ),
      ),
    );
    expect(transcript.events.map((event) => event.seq), [1, 2]);

    transcript.apply(
      ToolResultEvent(
        3,
        DateTime.fromMillisecondsSinceEpoch(3),
        const {},
        turn: 1,
        step: 1,
        message: const Message(
          id: 'message-2',
          role: MessageRole.tool,
          parts: [],
          source: MessageSource('tool', {}),
          toolCallId: 'call-1',
        ),
        surfaceOp: const {'op': 'replace', 'startSeq': 1, 'endSeq': 2},
      ),
    );
    expect(transcript.events.map((event) => event.seq), [3]);
  });

  test('session records keep an outer surfaceOp on their event', () {
    final event = SessionLogEvent.fromJson(
      {
        'seq': 4,
        'time': 4,
        'type': 'tool/result',
        'data': {
          'turn': 1,
          'step': 1,
          'message': {
            'id': 'message-3',
            'role': 'tool',
            'parts': <Object?>[],
            'source': {'kind': 'tool'},
            'toolCallId': 'call-1',
          },
        },
      },
      surfaceOp: const {'op': 'replace', 'startSeq': 1, 'endSeq': 2},
    );
    expect(event, isA<ToolResultEvent>());
    expect((event as ToolResultEvent).surfaceOp, isNotNull);
  });
}
