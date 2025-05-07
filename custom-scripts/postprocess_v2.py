import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

# Load data
datadir = '.'
files = [x for x in os.listdir(datadir) if x.endswith('.csv') and x.startswith('output')]
files.sort()
files = [os.path.join(datadir, file) for file in files]

# Define colors for datasets and markers for memory types
def get_color_list(n):
    cmap = plt.get_cmap('tab10')
    return [cmap(i % 10) for i in range(n)]

memory_types = ['L1', 'L2', 'GDDR6']
markers = {'L1': 'o', 'L2': '^', 'GDDR6': 's'}

# Read and process CSV files
dfs = {}
for file in files:
    tag, ext = os.path.splitext(os.path.basename(file))
    dfs[tag] = pd.DataFrame()
    with open(file, 'r') as f:
        cnt = 0
        while True:
            ln = f.readline()
            if not ln:
                break
            cnt += 1
            if 'Host Name' in ln:
                break
        df = pd.read_csv(file, skiprows=cnt-1)

        df['Metric Value'] = df['Metric Value'].replace(',', '', regex=True).astype(float)

        dft = df.groupby(['Kernel Name', 'Metric Name'])['Metric Value'].sum().reset_index()
        dfmetric = pd.pivot_table(dft, index='Kernel Name', columns='Metric Name', values='Metric Value')

        dfmetric['Count'] = df.groupby(['Kernel Name']).count()['ID'].div(dfmetric.shape[1])

        dfmetric['Time'] = dfmetric['sm__cycles_elapsed.avg'] \
                            / (dfmetric['sm__cycles_elapsed.avg.per_second'] / dfmetric['Count'])

        dfmetric['CC FLOPs'] = 2 * dfmetric['sm__sass_thread_inst_executed_op_dfma_pred_on.sum'] \
                              + dfmetric['sm__sass_thread_inst_executed_op_dmul_pred_on.sum'] \
                              + dfmetric['sm__sass_thread_inst_executed_op_dadd_pred_on.sum'] \
                              + 2 * dfmetric['sm__sass_thread_inst_executed_op_ffma_pred_on.sum'] \
                              + dfmetric['sm__sass_thread_inst_executed_op_fmul_pred_on.sum'] \
                              + dfmetric['sm__sass_thread_inst_executed_op_fadd_pred_on.sum'] \
                              + 2 * dfmetric['sm__sass_thread_inst_executed_op_hfma_pred_on.sum'] \
                              + dfmetric['sm__sass_thread_inst_executed_op_hmul_pred_on.sum'] \
                              + dfmetric['sm__sass_thread_inst_executed_op_hadd_pred_on.sum']

        dfmetric['TC FLOPs'] = 512 * dfmetric['sm__inst_executed_pipe_tensor.sum']
        dfmetric['all FLOPs'] = dfmetric['CC FLOPs'] + dfmetric['TC FLOPs']

        dfmetric['AI GDDR6'] = dfmetric['all FLOPs'].div(dfmetric['dram__bytes.sum'])
        dfmetric['AI L2'] = dfmetric['all FLOPs'].div(dfmetric['lts__t_bytes.sum'])
        dfmetric['AI L1'] = dfmetric['all FLOPs'].div(dfmetric['l1tex__t_bytes.sum'])

        dfmetric['GFLOP/s'] = dfmetric['all FLOPs'] / dfmetric['Time'] / 1024 / 1024 / 1024
        dfmetric['TC GFLOP/s'] = dfmetric['TC FLOPs'] / dfmetric['Time'] / 1024 / 1024 / 1024

        dfmetric.to_csv('pd_'+tag+'.csv')

        dfs[tag] = dfmetric

# Now plot everything in one figure
fig, ax = plt.subplots(figsize=(14, 10))

colors = get_color_list(len(dfs))
all_AI = []
all_GFLOPS = []

for idx, (tag, dfm) in enumerate(dfs.items()):
    color = colors[idx]
    LABELS = dfm.index.tolist()
    FLOPS = dfm['GFLOP/s'].tolist()

    first_point = True

    for mem_type in memory_types:
        if mem_type == 'L1':
            AI = dfm['AI L1'].tolist()
        elif mem_type == 'L2':
            AI = dfm['AI L2'].tolist()
        elif mem_type == 'GDDR6':
            AI = dfm['AI GDDR6'].tolist()

        for i in range(len(LABELS)):
            ax.scatter(AI[i], FLOPS[i], color=color, marker=markers[mem_type],
                       label=tag if first_point else None)
            first_point = False
            all_AI.append(AI[i])
            all_GFLOPS.append(FLOPS[i])

# Define theoretical peaks (for RTX 4060 roughly)
peak_sp_gflops = 12400  # Single precision (SP)
peak_dp_gflops = 200    # Double precision (DP)

bw_l1 = 5000  # GB/s
bw_l2 = 750
bw_gddr6 = 256

# Adaptive axis limits based on real data but ensure DP Peak is visible
xmin = min(all_AI) * 0.5
xmax = max(all_AI) * 2
ymin = min(all_GFLOPS) * 0.5
ymax = max(max(all_GFLOPS) * 2, peak_dp_gflops * 1.2)

ax.set_xlim([xmin, xmax])
ax.set_ylim([ymin, ymax])

# Set X range for roofline lines
x = np.logspace(np.log10(xmin), np.log10(xmax), 100)

# Plot memory ceilings
ax.plot(x, np.minimum(bw_l1 * x, peak_sp_gflops), label='L1 : {:.1f} GB/s'.format(bw_l1), color='black', linestyle='--')
ax.plot(x, np.minimum(bw_l2 * x, peak_sp_gflops), label='L2 : {:.1f} GB/s'.format(bw_l2), color='black', linestyle='--')
ax.plot(x, np.minimum(bw_gddr6 * x, peak_sp_gflops), label='GDDR6 : {:.1f} GB/s'.format(bw_gddr6), color='black', linestyle='--')

# Plot compute ceilings
ax.hlines(peak_sp_gflops, xmin, xmax, colors='red', linestyles='solid', label='SP Peak {:.1f} TFLOP/s'.format(peak_sp_gflops/1000))
ax.hlines(peak_dp_gflops, xmin, xmax, colors='blue', linestyles='solid', label='DP Peak {:.1f} TFLOP/s'.format(peak_dp_gflops/1000))

# Grid, labels
ax.set_xlabel('Arithmetic Intensity (FLOPs/Byte)')
ax.set_ylabel('Performance (GFLOP/s)')
ax.set_xscale('log')
ax.set_yscale('log')
ax.grid(True, which='both')
ax.set_title('Roofline Plot: All Datasets (L1, L2, GDDR6)')

# Move legend outside
handles, labels = ax.get_legend_handles_labels()
unique_labels = dict(zip(labels, handles))  # Remove duplicates
ax.legend(unique_labels.values(), unique_labels.keys(), fontsize='small', loc='center left', bbox_to_anchor=(1, 0.5))

plt.tight_layout()
plt.savefig('roofline_all_in_one_L1_L2_GDDR6_fixed.png', dpi=300, bbox_inches='tight')
plt.show()