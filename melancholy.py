import random, time, os
from mido import MidiFile, MidiTrack, Message, MetaMessage, bpm2tempo

seed = time.time_ns() ^ os.getpid()
random.seed(seed)
print(f"本次随机种子: {seed}")

BPM = 60
TPB = 480
BAR = 4 * TPB
BARS = 44
TOTAL = BARS * BAR

mid = MidiFile(type=1, ticks_per_beat=TPB)

chords = {
    'Am': [57, 60, 64, 69],
    'F':  [53, 57, 60, 65],
    'C':  [48, 55, 60, 64],
    'G':  [55, 59, 62, 67],
    'Dm': [50, 57, 62, 65],
    'E7': [52, 56, 59, 62],
}

progression = ['Am', 'F', 'C', 'G', 'Am', 'Dm', 'E7', 'Am']
bar_chords = [progression[i % len(progression)] for i in range(BARS)]

scale = [57, 59, 60, 62, 64, 65, 67, 69, 71, 72, 74, 76]

CH_PIANO = 0
CH_CELLO = 1
CH_VIOLIN = 2
CH_PAD = 3
CH_BOX = 4

piano_events = []
cello_events = []
violin_events = []
pad_events = []
box_events = []

for bar in range(BARS):
    chord_name = bar_chords[bar]
    chord_notes = chords[chord_name]
    bar_start = bar * BAR

    for i in range(8):
        tick = bar_start + i * (TPB // 2)
        note = random.choice(chord_notes)
        if random.random() < 0.2:
            note += 12
        vel = random.randint(40, 60)
        dur = TPB // 2 - 10
        piano_events.append((tick, Message('note_on', note=note, velocity=vel, channel=CH_PIANO)))
        piano_events.append((tick + dur, Message('note_off', note=note, velocity=0, channel=CH_PIANO)))

    root = chord_notes[0] - 12
    if root < 36:
        root += 12
    tick = bar_start
    vel = random.randint(45, 65)
    dur = BAR - 20
    cello_events.append((tick, Message('note_on', note=root, velocity=vel, channel=CH_CELLO)))
    cello_events.append((tick + dur, Message('note_off', note=root, velocity=0, channel=CH_CELLO)))

    if random.random() < 0.4:
        fifth = root + 7
        tick2 = bar_start + 2 * TPB
        cello_events.append((tick2, Message('note_on', note=fifth, velocity=vel - 10, channel=CH_CELLO)))
        cello_events.append((tick2 + TPB, Message('note_off', note=fifth, velocity=0, channel=CH_CELLO)))

    pos = 0
    while pos < BAR:
        choices = [TPB, TPB * 2, TPB // 2, TPB * 3 // 2]
        dur = random.choice(choices)
        if pos + dur > BAR:
            dur = BAR - pos
        if dur < TPB // 4:
            break

        if random.random() < 0.7:
            note = random.choice(chord_notes) + 12
            if random.random() < 0.3:
                note += 12
        else:
            note = random.choice(scale) + 12

        note = max(60, min(84, note))
        vel = random.randint(50, 75)
        tick = bar_start + pos
        violin_events.append((tick, Message('note_on', note=note, velocity=vel, channel=CH_VIOLIN)))
        violin_events.append((tick + dur - 10, Message('note_off', note=note, velocity=0, channel=CH_VIOLIN)))

        pos += dur
        if random.random() < 0.3:
            pos += TPB // 2

    if bar % 2 == 0:
        notes = chord_notes[:]
        random.shuffle(notes)
        for n in notes:
            tick = bar_start
            dur = BAR * 2 - 40
            vel = random.randint(25, 40)
            pad_events.append((tick, Message('note_on', note=n, velocity=vel, channel=CH_PAD)))
            pad_events.append((tick + dur, Message('note_off', note=n, velocity=0, channel=CH_PAD)))

    n_notes = random.randint(0, 2)
    for _ in range(n_notes):
        tick = bar_start + random.randint(0, BAR - TPB // 2)
        note = random.choice(chord_notes) + 24
        note = min(96, note)
        vel = random.randint(30, 50)
        dur = TPB // 2
        box_events.append((tick, Message('note_on', note=note, velocity=vel, channel=CH_BOX)))
        box_events.append((tick + dur, Message('note_off', note=note, velocity=0, channel=CH_BOX)))

def build_track(program, channel, events, name):
    track = MidiTrack()
    track.append(MetaMessage('track_name', name=name, time=0))
    track.append(Message('program_change', program=program, channel=channel, time=0))
    events.sort(key=lambda x: x[0])
    last = 0
    for tick, msg in events:
        delta = tick - last
        msg.time = delta
        track.append(msg)
        last = tick
    return track

track_piano = build_track(0,  CH_PIANO,  piano_events,  'Piano')
track_cello = build_track(42, CH_CELLO,  cello_events,  'Cello')
track_violin = build_track(40, CH_VIOLIN, violin_events, 'Violin')
track_pad = build_track(89, CH_PAD,    pad_events,    'Pad')
track_box = build_track(10, CH_BOX,    box_events,    'Music Box')

tempo_track = MidiTrack()
tempo_track.append(MetaMessage('set_tempo', tempo=bpm2tempo(BPM), time=0))
tempo_track.append(MetaMessage('time_signature', numerator=4, denominator=4, time=0))
tempo_track.append(MetaMessage('end_of_track', time=TOTAL))

mid.tracks.insert(0, tempo_track)
mid.tracks.append(track_piano)
mid.tracks.append(track_cello)
mid.tracks.append(track_violin)
mid.tracks.append(track_pad)
mid.tracks.append(track_box)

os.makedirs('/workspace/midi', exist_ok=True)
filename = f"/workspace/midi/melancholy_unique_{seed}.mid"
mid.save(filename)

print(f"已生成: {filename}")
print(f"长度: {BARS} 小节, BPM={BPM}, 约 {BARS * 4 * 60 / BPM:.1f} 秒")
