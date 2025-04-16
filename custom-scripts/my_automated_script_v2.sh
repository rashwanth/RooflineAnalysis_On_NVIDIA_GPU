#!/bin/bash

# Load environment (adjust if needed for local setup)
# export PATH=/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/bin:$PATH
# export PATH=/usr/local/cuda/bin:$PATH  # if needed

# Set Nsight Compute metrics
metrics="sm__cycles_elapsed.avg,\\
sm__cycles_elapsed.avg.per_second,\\
sm__sass_thread_inst_executed_op_dadd_pred_on.sum,\\
sm__sass_thread_inst_executed_op_dfma_pred_on.sum,\\
sm__sass_thread_inst_executed_op_dmul_pred_on.sum,\\
sm__sass_thread_inst_executed_op_fadd_pred_on.sum,\\
sm__sass_thread_inst_executed_op_ffma_pred_on.sum,\\
sm__sass_thread_inst_executed_op_fmul_pred_on.sum,\\
sm__sass_thread_inst_executed_op_hadd_pred_on.sum,\\
sm__sass_thread_inst_executed_op_hfma_pred_on.sum,\\
sm__sass_thread_inst_executed_op_hmul_pred_on.sum,\\
sm__inst_executed_pipe_tensor.sum,\\
dram__bytes.sum,\\
lts__t_bytes.sum,\\
l1tex__t_bytes.sum"

# Move to source directory
cd ../example-codes/GPP/

input=gpp214unformatted.dat
dir=../../custom-scripts/

# Function to profile and extract CSV
profile_and_extract() {
    local output_csv=$1
    local repfile=${output_csv%.csv}.ncu-rep

    ncu --launch-skip 0 --launch-count 1 -k sigma_gpp_gpu --metrics $metrics --csv --export $repfile ./gpp.x $input
    ncu --import $repfile --csv --section ComputeWorkloadAnalysis > $output_csv
}

# Baseline
echo "Baseline version"
git checkout gpp.f90
make clean
make FC=nvfortran FLAGS="-acc -gpu=cc89 -Minfo=accel -fast -Mfree -mp -Mlarge_arrays"
profile_and_extract $dir/output.csv

# Apply patch optimizations step-by-step
for n in $(seq 1 2); do
    output_csv="$dir/output${n}.csv"
    echo "Patch version: $n"
    git checkout gpp.f90
    patch gpp.f90 step$n.patch
    make clean && make
    profile_and_extract $output_csv
done

# Done
echo "Profiling complete. Output saved in $dir/"
