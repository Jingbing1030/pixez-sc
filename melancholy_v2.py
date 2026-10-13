"""忧郁华尔兹 v2：连贯和声、乐句化旋律、混响与力度起伏。"""
import random, time, os
from mido import MidiFile, MidiTrack, Message, MetaMessage, bpm2tempo

seed = time.time_ns() ^ os.getpid()
random.seed(seed)
print(f"本次随机种子: {seed}")

BPM = 72
TPB = 480
BEAT = TPB
BAR = 4 * BEAT
BARS = 48
TOTAL = BARS * BAR

CH_PIANO, CH_CELLO, CH_VIOLIN, CH_PAD, CH_BOX = 0, 1, 2, 3, 4

chords = {
    'Am': [57, 60, 64, 69],
    'F':  [53, 57, 60, 65],
    'C':  [55, 60, 64, 72],
    'G':  [55, 59, 62, 67],
    'Dm': [50, 57, 62, 65],
    'E7': [52, 56, 59, 62],
}
prog = ['Am', 'F', 'C', 'G', 'Am', 'Dm', 'E7', 'Am']
bar_chords = [prog[i % 8] for i in range(BARS)]
roots = {'Am': 45, 'F': 41, 'C': 48, 'G': 43, 'Dm': 38, 'E7': 40}
scale = [57, 59, 60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79]

piano, cello, violin, pad, box = [], [], [], [], []
LISTS = {CH_PIANO: piano, CH_CELLO: cello, CH_VIOLIN: violin, CH_PAD: pad, CH_BOX: box}

def note(lst, tick, dur, n, vel, ch):
    lst.append((tick, Message('note_on', note=n, velocity=vel, channel=ch)))
    lst.append((tick + dur, Message('note_off', note=n, velocity=0, channel=ch)))

def melody_phrase(start_bar, chord_seq):
    """生成 4 小节的旋律：级进为主，偶尔跳进，末句落在和弦音上。"""
    out = []
    cur = random.choice([69, 72, 76])
    for b in range(4):
        ch = chords[chord_seq[b]]
        pos = 0
        while pos < BAR:
            dur = min(BAR - pos, random.choice([BEAT, BEAT, BEAT * 2, BEAT * 3 // 2, BEAT // 2]))
            if b == 3 and pos + dur == BAR:
                cand = min(ch, key=lambda n: abs(n + 12 - cur)) + 12
            elif pos == 0 and random.random() < 0.4:
                cand = random.choice(ch) + 12
            else:
                idx = min(range(len(scale)), key=lambda i: abs(scale[i] - cur))
                step = random.choice([-2, -1, -1, 1, 1, 2]) if random.random() < 0.8 else random.choice([-4, 3, 4])
                cand = scale[max(0, min(len(scale) - 1, idx + step))]
            cand = max(62, min(84, cand))
            if random.random() < 0.85:
                out.append((start_bar * BAR + b * BAR + pos, dur, cand, b))
            cur = cand
            pos += dur
            if random.random() < 0.15 and pos < BAR:
                pos += BEAT // 2
    return out

for bar in range(BARS):
    c = bar_chords[bar]
    cn = chords[c]
    s = bar * BAR
    pp = bar % 4
    env = [0.85, 1.0, 1.05, 0.8][pp]
    intro = bar < 2
    outro = bar >= BARS - 4
    fade = 1.0 if not outro else max(0.25, 1 - (bar - (BARS - 4)) * 0.25)

    # 钢琴：Alberti 式分解，强拍重、弱拍轻
    if not intro:
        pattern = [0, 2, 1, 3, 2, 1, 2, 0] if pp % 2 == 0 else [0, 1, 2, 3, 1, 2, 3, 2]
        for i, idx in enumerate(pattern):
            t = s + i * (BEAT // 2) + random.randint(-6, 6)
            n = cn[idx] + (12 if i % 4 == 0 and random.random() < 0.15 else 0)
            base = 52 if i % 2 == 0 else 40
            vel = int((base + random.randint(-4, 6)) * env * fade)
            note(piano, max(0, t), BEAT // 2 - 30, n, max(20, min(90, vel)), CH_PIANO)

    # 大提琴：根音 + 五度
    if not intro:
        r = roots[c]
        v = int(55 * env * fade) + random.randint(-3, 3)
        note(cello, s, 2 * BEAT - 40, r, v, CH_CELLO)
        note(cello, s + 2 * BEAT, 2 * BEAT - 40, r + 7 if random.random() < 0.6 else r, v - 6, CH_CELLO)

    # 小提琴：每 4 小节一段乐句
    if pp == 0 and bar + 4 <= BARS:
        for (t, dur, n, b) in melody_phrase(bar // 4, bar_chords[bar:bar + 4]):
            vel = int((58 + 14 * [0.3, 0.7, 1.0, 0.5][b]) * fade) + random.randint(-4, 4)
            note(violin, t, dur - 20, n, max(35, min(100, vel)), CH_VIOLIN)

    # Pad：每两小节一组柔和和弦
    if bar % 2 == 0:
        for n in sorted(cn):
            vel = int(28 * fade) + random.randint(-2, 4)
            note(pad, s, 2 * BAR - 60, n - 12 if n > 60 else n, max(18, vel), CH_PAD)

    # 音乐盒：稀疏点缀
    if not intro and random.random() < 0.5:
        for _ in range(random.randint(1, 2)):
            t = s + random.choice([BEAT // 2, BEAT + BEAT // 2, 2 * BEAT + BEAT // 2, 3 * BEAT + BEAT // 2])
            n = min(96, random.choice(cn) + 24)
            note(box, t + random.randint(-4, 4), BEAT // 2, n,
                 int(random.randint(34, 48) * fade), CH_BOX)

# 控制器：混响(91)、音量(7)、声像(10)
for ch, rev, vol, pan in [(CH_PIANO, 45, 100, 56), (CH_CELLO, 60, 95, 40),
                          (CH_VIOLIN, 75, 105, 72), (CH_PAD, 95, 85, 64),
                          (CH_BOX, 80, 90, 80)]:
    for ctrl, val in [(91, rev), (7, vol), (10, pan)]:
        LISTS[ch].append((0, Message('control_change', control=ctrl, value=val, channel=ch)))

ORDER = {'control_change': 0, 'note_off': 1, 'note_on': 2}
def build_track(program, channel, events, name):
    track = MidiTrack()
    track.append(MetaMessage('track_name', name=name, time=0))
    track.append(Message('program_change', program=program, channel=channel, time=0))
    events.sort(key=lambda x: (x[0], ORDER.get(x[1].type, 3)))
    last = 0
    for tick, msg in events:
        msg.time = tick - last
        track.append(msg)
        last = tick
    return track

tempo_track = MidiTrack()
tempo_track.append(MetaMessage('track_name', name='Tempo', time=0))
tempo_track.append(MetaMessage('set_tempo', tempo=bpm2tempo(BPM), time=0))
tempo_track.append(MetaMessage('time_signature', numerator=4, denominator=4, time=0))
tempo_track.append(MetaMessage('end_of_track', time=TOTAL))

mid = MidiFile(type=1, ticks_per_beat=TPB)
mid.tracks.append(tempo_track)
mid.tracks.append(build_track(0, CH_PIANO, piano, 'Piano'))
mid.tracks.append(build_track(42, CH_CELLO, cello, 'Cello'))
mid.tracks.append(build_track(40, CH_VIOLIN, violin, 'Violin'))
mid.tracks.append(build_track(89, CH_PAD, pad, 'Pad'))
mid.tracks.append(build_track(10, CH_BOX, box, 'Music Box'))

os.makedirs('/workspace/midi', exist_ok=True)
filename = f"/workspace/midi/melancholy_v2_{seed}.mid"
mid.save(filename)
print(f"已生成: {filename}")
print(f"长度: {BARS} 小节, BPM={BPM}, 约 {BARS * 4 * 60 / BPM:.1f} 秒")
