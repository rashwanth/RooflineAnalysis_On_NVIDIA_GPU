#!/bin/bash

# Load environment (adjust if needed for your local setup)
# export PATH=/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/bin:$PATH
# export PATH=/usr/local/cuda/bin:$PATH

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
output="$dir/output0"

echo "Baseline version"
git checkout gpp.f90
make clean
make FC=nvfortran FLAGS="-acc -gpu=cc89 -Minfo=accel -fast -Mfree -mp -Mlarge_arrays"

# Run and profile with Nsight Compute using Roofline section
ncu --section SpeedOfLight_HierarchicalDoubleRooflineChart --section Occupancy --metrics sm__warps_active.avg,sm__warps_active.avg.pct_of_peak_sustained_active,sm__warps_launched.avg,smsp__inst_executed_pipe_fp64_fma.sum,smsp__inst_executed_pipe_fp64_mul.sum,smsp__inst_executed_pipe_fp64_add.sum --export "$output" -f ./gpp.x "$input"

# Loop over all gpp versions (gpp1.f90 to gpp8.f90)
for i in {8..8}; do
    version_file="gpp${i}.f90"
    output_rep="$dir/output${i}"

    echo "🔁 Running version: $version_file"

    # Copy the version to gpp.f90
    cp "$version_file" gpp.f90

    # Clean and compile
    make clean
    make FC=nvfortran FLAGS="-acc -gpu=cc89 -Minfo=accel -fast -Mfree -mp -Mlarge_arrays"

    # Run and profile with Nsight Compute
    ncu --section SpeedOfLight_HierarchicalDoubleRooflineChart --section Occupancy --metrics sm__warps_active.avg,sm__warps_active.avg.pct_of_peak_sustained_active,sm__warps_launched.avg,smsp__inst_executed_pipe_fp64_fma.sum,smsp__inst_executed_pipe_fp64_mul.sum,smsp__inst_executed_pipe_fp64_add.sum --export "$output_rep" -f ./gpp.x "$input"
done

# Restore original file
cp gpp_original_backup.f90 gpp.f90
rm gpp_original_backup.f90

echo "✅ All profiling complete. Check .ncu-rep reports in: $dir/"
