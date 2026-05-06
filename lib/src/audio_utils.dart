import 'dart:typed_data';

Uint8List ensureWavAudio({
  required Uint8List audio,
  required String codec,
  required int sampleRateHz,
  required int channels,
}) {
  if (looksLikeWav(audio) || codec.toLowerCase() == 'wav') {
    return audio;
  }
  return pcm16ToWav(pcm: audio, sampleRateHz: sampleRateHz, channels: channels);
}

bool looksLikeWav(Uint8List data) {
  if (data.length < 12) {
    return false;
  }
  return String.fromCharCodes(data.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(data.sublist(8, 12)) == 'WAVE';
}

Uint8List pcm16ToWav({
  required Uint8List pcm,
  required int sampleRateHz,
  required int channels,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRateHz * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final fileSizeMinus8 = 36 + pcm.length;
  final out = BytesBuilder();
  out.add(_ascii('RIFF'));
  out.add(_u32(fileSizeMinus8));
  out.add(_ascii('WAVE'));
  out.add(_ascii('fmt '));
  out.add(_u32(16));
  out.add(_u16(1));
  out.add(_u16(channels));
  out.add(_u32(sampleRateHz));
  out.add(_u32(byteRate));
  out.add(_u16(blockAlign));
  out.add(_u16(bitsPerSample));
  out.add(_ascii('data'));
  out.add(_u32(pcm.length));
  out.add(pcm);
  return out.toBytes();
}

Uint8List _ascii(String text) => Uint8List.fromList(text.codeUnits);

Uint8List _u16(int value) {
  final bytes = ByteData(2)..setUint16(0, value, Endian.little);
  return bytes.buffer.asUint8List();
}

Uint8List _u32(int value) {
  final bytes = ByteData(4)..setUint32(0, value, Endian.little);
  return bytes.buffer.asUint8List();
}
