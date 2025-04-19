#!/bin/bash

# Load environment (adjust if needed for local setup)
# export PATH=/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/bin:$PATH
# export PATH=/usr/local/cuda/bin:$PATH  # if needed

# Set Nsight Compute metrics
metrics="sm__cycles_elapsed.avg,\
sm__cycles_elapsed.avg.per_second,\
sm__sass_thread_inst_executed_op_dadd_pred_on.sum,\
sm__sass_thread_inst_executed_op_dfma_pred_on.sum,\
sm__sass_thread_inst_executed_op_dmul_pred_on.sum,\
sm__sass_thread_inst_executed_op_fadd_pred_on.sum,\
sm__sass_thread_inst_executed_op_ffma_pred_on.sum,\
sm__sass_thread_inst_executed_op_fmul_pred_on.sum,\
sm__sass_thread_inst_executed_op_hadd_pred_on.sum,\
sm__sass_thread_inst_executed_op_hfma_pred_on.sum,\
sm__sass_thread_inst_executed_op_hmul_pred_on.sum,\
sm__inst_executed_pipe_tensor.sum,\
dram__bytes.sum,\
lts__t_bytes.sum,\
l1tex__t_bytes.sum"

# Move to source directory
cd ../example-codes/GPP/

input=gpp214unformatted.dat
dir=../../custom-scripts/

# Baseline
output=output.csv
#profilestr="ncu -k sigma_gpp_gpu --metrics $metrics --csv"
#profilestr="ncu --launch-skip 0 --launch-count 1 -k sigma_gpp_gpu --metrics $metrics --csv"
profilestr="ncu --launch-skip 0 --launch-count 1 --metrics "$metrics" --csv ./gpp.x $input > $dir/$output 2>&1"

echo "Baseline version"
git checkout gpp.f90
make clean
make FC=nvfortran FLAGS="-acc -gpu=cc89 -Minfo=accel -fast -Mfree -mp -Mlarge_arrays"
$profilestr ./gpp.x $input > $dir/$output 2>&1
#$profilestr --export $dir/$output ./gpp.x $input

for n in $(seq 1 4); do
    output="output$n.csv"
    echo "Patch version: $n"

    # Start fresh every time
    git checkout -- gpp.f90  # <- safer than just "checkout gpp.f90"

    # Check if patch is already applied
    if patch --dry-run gpp.f90 < step$n.patch > /dev/null; then
        patch gpp.f90 < step$n.patch
    else
        echo "⚠️ Patch step$n.patch appears already applied or doesn't fit. Skipping..."
        continue
    fi

    make clean && make
    $profilestr ./gpp.x $input > $dir/$output 2>&1
done


# Done
echo "Profiling complete. Output saved in $dir/"
