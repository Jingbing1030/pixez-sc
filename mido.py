"""Minimal stand-in for the parts of mido used by the melancholy generator."""
import struct

def bpm2tempo(bpm):
    return round(60_000_000 / bpm)

def _vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.insert(0, (n & 0x7F) | 0x80)
        n >>= 7
    return bytes(out)

class Message:
    def __init__(self, type, time=0, **kw):
        self.type = type
        self.time = time
        self.__dict__.update(kw)

    def to_bytes(self):
        ch = getattr(self, 'channel', 0)
        if self.type == 'note_on':
            return bytes([0x90 | ch, self.note, self.velocity])
        if self.type == 'note_off':
            return bytes([0x80 | ch, self.note, self.velocity])
        if self.type == 'program_change':
            return bytes([0xC0 | ch, self.program])
        raise ValueError(self.type)

class MetaMessage(Message):
    def to_bytes(self):
        if self.type == 'track_name':
            d = self.name.encode('utf-8'); return b'\xff\x03' + _vlq(len(d)) + d
        if self.type == 'set_tempo':
            return b'\xff\x51\x03' + self.tempo.to_bytes(3, 'big')
        if self.type == 'time_signature':
            return b'\xff\x58\x04' + bytes([self.numerator, int(np_log2(self.denominator)), 24, 8])
        if self.type == 'end_of_track':
            return b'\xff\x2f\x00'
        raise ValueError(self.type)

def np_log2(x):
    n = 0
    while x > 1:
        x //= 2; n += 1
    return n

class MidiTrack(list):
    def to_bytes(self):
        body = b''.join(_vlq(m.time) + m.to_bytes() for m in self)
        return b'MTrk' + struct.pack('>I', len(body)) + body

class MidiFile:
    def __init__(self, type=1, ticks_per_beat=480):
        self.type = type
        self.ticks_per_beat = ticks_per_beat
        self.tracks = []

    def save(self, filename):
        data = b'MThd' + struct.pack('>IHHH', 6, self.type, len(self.tracks), self.ticks_per_beat)
        data += b''.join(t.to_bytes() for t in self.tracks)
        with open(filename, 'wb') as f:
            f.write(data)
