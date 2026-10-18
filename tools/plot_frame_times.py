#!/usr/bin/env python3
"""Plot Wine frame-interval CSVs: LABEL=CSV [...] --out plot.png."""
import argparse
import csv
from pathlib import Path
import statistics
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('series', nargs='+', help='LABEL=CSV')
p.add_argument('--out', type=Path, required=True)
p.add_argument('--title', default='NTSD frame submission timing')
p.add_argument('--note', default='Wine trace resolution: 1 ms. Submission timing is not display presentation latency.')
a = p.parse_args()
fig, axes = plt.subplots(1, 2, figsize=(11, 4.6), gridspec_kw={'width_ratios': [1.6, 1]})
colors = ['#1765a5', '#d97913', '#3c8c64']
for item, color in zip(a.series, colors):
    label, file = item.split('=', 1)
    with Path(file).open() as f:
        rows = list(csv.DictReader(f))
    times = [float(r['relative_s']) for r in rows]
    intervals = [float(r['frame_ms']) for r in rows]
    q = statistics.quantiles(intervals, n=100, method='inclusive')
    fps = 1000 * len(intervals) / sum(intervals)
    axes[0].plot(times, intervals, color=color, linewidth=.7, alpha=.75, label=label)
    ordered = sorted(intervals)
    axes[1].step(ordered, [100*(i+1)/len(ordered) for i in range(len(ordered))],
                 where='post', color=color,
                 label=f'{label}: {fps:.2f} FPS, p99 {q[98]:.0f} ms')
for ax in axes:
    ax.grid(alpha=.2)
    ax.spines[['top', 'right']].set_visible(False)
axes[0].set(xlabel='Time in selected interval (s)', ylabel='Frame submission interval (ms)', ylim=(0, None))
axes[0].legend(frameon=False, fontsize=9, loc='upper right')
axes[1].set(xlabel='Frame submission interval (ms)', ylabel='Intervals at or below value (%)', ylim=(0, 101), xlim=(0, None))
axes[1].legend(frameon=False, fontsize=8, loc='lower right')
fig.suptitle(a.title, x=.08, ha='left', fontsize=14, fontweight='bold')
fig.text(.08, .025, a.note, fontsize=8, color='#444444')
fig.tight_layout(rect=(.02,.07,1,.92))
a.out.parent.mkdir(parents=True, exist_ok=True)
fig.savefig(a.out, dpi=150, facecolor='white')
print(a.out)
