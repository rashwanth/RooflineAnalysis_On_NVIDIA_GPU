#!/bin/bash

# Load environment (adjust if needed for your local setup)
# export PATH=/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/bin:$PATH
# export PATH=/usr/local/cuda/bin:$PATH

# Nsight Compute metrics
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

# Move to source code directory
cd ../example-codes/GPP/

# Input file for the GPP executable
input="gpp214unformatted.dat"

# Output directory (make sure it exists)
dir="../../custom-scripts"
mkdir -p "$dir"

# Backup original gpp.f90
cp gpp.f90 gpp_original_backup.f90

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

# Loop over all gpp versions (gpp0.f90 to gpp8.f90)
for i in {1..8}; do
    version_file="gpp${i}.f90"
    output_csv="$dir/output${i}.csv"

    echo "🔁 Running version: $version_file"

    # Copy the version to gpp.f90
    cp "$version_file" gpp.f90

    # Clean and compile
    make clean
    make FC=nvfortran FLAGS="-acc -gpu=cc89 -Minfo=accel -fast -Mfree -mp -Mlarge_arrays"

    # Run and profile with Nsight Compute
    ncu --launch-skip 0 --launch-count 1 --metrics "$metrics" --csv ./gpp.x "$input" > "$output_csv" 2>&1
done

# Restore original file
cp gpp_original_backup.f90 gpp.f90
rm gpp_original_backup.f90

echo "✅ All profiling complete. Check output CSVs in: $dir/"
