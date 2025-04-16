**This repo has been restructured since the Roofline Hackathon on July 8, 2020. If you would like to use the same code, please check out this tag: [roofline-hackathon-2020](https://gitlab.com/NERSC/roofline-on-nvidia-gpus/-/tree/roofline-hackathon-2020).**

**There is a more detailed description of the optimizations (8 steps) done on GPP. Please see [the paper here](https://arxiv.org/abs/2008.11326) and the code on [the arxiv-paper branch](https://gitlab.com/NERSC/roofline-on-nvidia-gpus/-/tree/arxiv-paper).**

**Please contact Charlene Yang (<cjyang@lbl.gov>) if there are any questions or issues regarding the Roofline methodology in this repository.**

# Roofline Model on NVIDIA GPUs

This repo demonstrates the use of Roofline analysis on NVIDIA GPUs especially on V100s. 
The Roofline performance model provides an intuitive and insightful way to understand application performance, identify bottlenecks and perform optimization for HPC applications. 
For more details on Roofline, please visit [this page](https://crd.lbl.gov/departments/computer-science/PAR/research/roofline/).

The methodology for Roofline data collection on NVIDIA GPUs has evolved from using nvprof ([github: nersc-roofline](https://github.com/cyanguwa/nersc-roofline)), to Nsight Compute in CUDA 10 ([tag: cuda10.2.89-ncu](https://gitlab.com/NERSC/roofline-on-nvidia-gpus/-/tree/cuda10.2.89-ncu)), and now to Nsight Compute in CUDA 11 ([tag: cuda11.0.2-ncu](https://gitlab.com/NERSC/roofline-on-nvidia-gpus/-/tree/cuda11.0.2-ncu)).
A few papers and talks have been published/presented to discuss this methodology and its efficacy:
 
- C. Yang, T. Kurth, and S. Williams, Hierarchical Roofline analysis for GPUs: Accelerating performance optimization for the NERSC‐9 Perlmutter system, Concurrency and Computation: Practice and Experience, e5547, 2019. https://doi.org/10.1002/cpe.5547
- C. Yang, S. Williams, and Y. Wang, Roofline Performance Model for HPC and Deep-Learning Applications, GPU Technology Conference (GTC), 2020. https://developer.nvidia.com/gtc/2020/video/s21565
- C. Yang, Hierarchical Roofline Analysis: How to Collect Data using Performance Tools on Intel CPUs and NVIDIA GPUs, arXiv:2009.02449, 2020. https://arxiv.org/abs/2009.02449 
- Y. Wang, C. Yang, S. Farrel, T. Kurth, and S. Williams, Hierarchical Roofline Analysis for Deep Learning Applications, IEEE International Workshop on Performance Modeling, Benchmarking and Simulation of High Performance Computer Systems Workshop (PMBS), 2020. https://arxiv.org/abs/2009.05257


The structure of this repo is as follows.

- [/example-codes](/example-codes) contains some toy kernels `kernel_abc.cu` and a real HPC mini-app GPP, extracted from the Material Science Code [BerkeleyGW](https://berkeleygw.org).
- [/ncu-section-files](/ncu-section-files) contains the default Speed of Light section files shipped with Nsight Compute in CUDA 11, and several custom section files used for hierarchical Roofline analysis, for double-precision, single-precision, half-precision and Tensor Core operations. These section files are intended for automatic Roofline data collection and visualization using Nsight Compute (`ncu`).
-  `run.ncu` demonstrates how to run Nsight Compute in CUDA 11, and `run.gpp.ncu` is a Slurm job script for running five versions of the GPP example on Cori GPU. 
- [/custom-scripts](/custom-scripts) provides a set of job launch, postprocessing and visualization scripts that can be used for manual Roofline data collection and visualization. The purpose of this is to make it easier for users to integrate Roofline analysis into their workflow. 


# Roofline Analysis Tutorial

## Three Toy Kernels

Before we analyze the real GPP example, let's play with some toy kernels to warm up using Nsight Compute to do roofline analysis.
The code `kernel_abc.cu` is a simple CUDA C++ code that contains three kernels, kernel_A, kernel_B, and kernel_C. Compile the code and
profile it with Nsight Compute, then load the report into the Nsight Compute UI:

```
cd example-codes/
nvcc -o kernel_abc kernel_abc.cu
ncu -f -o kernel_abc --set full ./kernel_abc
ncu-ui
```

kernel_A is an instruction throughput bound kernel: with each thread we do 10000 double precision adds, for an arithmetic intensity of
10000 / 8 (bytes per double precision word) = 1250. Clearly this is a contrived example, but our goal here is to examine whether the
tool supports our intuition that this should be in the compute-bound part of the roofline chart. Does Nsight Compute agree with that?

kernel_B is identical to kernel_A, except that we artificially throttle occupancy on the GPU by allocating 96 kB of shared memory per
threadblock, which means that only one threadblock can be resident on an SM at any one time, for an occupancy of 1/32 = 3.125%. This
kernel will likely be instruction latency bound -- it should have the same arithmetic intensity as kernel_A, but not be anywhere close
to the compute-bound roofline.

kernel_C is primarily memory-bandwidth bound -- we just do a single double precision add, combined with a load and a store (for an
arithmetic intensity of 1 / 16 = .0625). The memory access pattern is strided -- we load every element of B exactly once and store
every element of A exactly once, but any given warp is accessing memory locations 32 bytes apart between each thread. (Can you determine
which part of the memory subsystem ought to be the bottleneck for this kernel?)

Take some time to examine the Nsight Compute report for each kernel. Pay attention to not just the roofline chart but the rest of
the report as well: for all cases, does the information in the compute workload analysis, memory workload analysis, and instruction
statistics sections match your understanding of what should be going on in each kernel?

## The GPP Exercise

The GPP mini-app comes from the Sigma module of [BerkeleyGW](https://berkeleygw.org) and is a key part of the quasiparticle self-energy calculation.

The baseline version of the GPP code is provided as `gpp.f90` and `gpp_data.f90`, and an example input file and a makefile are available as well, `gpp214unformatted.dat` and `Makefile` in [/example-codes](/example-codes). It is accelerated with OpenACC using the PGI compiler. 

This baseline code can be thought of as the naive GPU port of the original CPU code, and we simply collapse the three available independent loops to expose maximum parallelism.
Four other versions are also available by applying the git patches in [/example-codes](/example-codes). 
These patches demonstrate four optimization steps to improve the kernel performance by 2.5x, and can be applied to the baseline code directly. 

A workflow we recommend is to first profile the baseline code, and then apply each patch
consecutively, collecting a new profile each time. You can load multiple report files into Nsight Compute and, if you like,
use the "Add Baseline" functionality to see multiple reports on the same roofline chart so you can see the progress made
in each step.

The git patches are cumulative, so the intended workflow is something like:

```
cd example-codes/GPP
../../run.ncu baseline

patch gpp.f90 step1.patch
../../run.ncu step1

git checkout gpp.f90
patch gpp.f90 step2.patch
../../run.ncu step2

...
```

### Step 1

In the baseline code, Roofline analysis reveals that this kernel is not compute-bound. However its arithmetic intensity
is just below the crossover point at which the kernel can be said to be compute bound. This suggests that if we do a little
work, we can get the application over to the compute bound regime, where we may be more likely to achieve a higher fraction
of peak performance. (Contrast this with a simple kernel that, say, copies one array to another -- there is no way to rewrite
this to move it from the bandwidth-bound regime to the compute-bound regime.)

Another consideration is that with any two of the three loops that are parallelized in the baseline code, we have enough
parallelism to saturate a modern GPU (which can have O(100,000) threads resident). So this is a case where we can inspect
a different parallelism strategy on at least one of the three loops without worrying that the resulting kernel will have
low occupancy on the GPU.

Combining these two strands of thought together, we could choose to collapse only two of the three loops, leaving the third
loop to be run sequentially by each thread. Since each thread would have more work, it is possible that the kernel could become
compute bound.

To choose which one to try, we should pay attention to the memory access patterns of the code. Fortran uses column major
memory ordering, so 2D arrays like wtilde_array and I_eps_array have locations indexed with ig adjacent to each other in
memory. Similarly, arrays like aqsmtemp_local have locations indexed with igp adjacent to each other in memory. So for all
of the multi-dimensional arrays the n1_loc has the largest stride between accesses. Effective use of GPU memory bandwidth
requires coalesced accesses where consecutive threads access consecutive locations in memory. So this all implies that the
n1_loc loop is the most logical target for this experiment.

When we try this, we find that the code may not actually speed up. However, we find that we have now definitely made the
kernel compute bound, with a double precision arithmetic intensity of around 20 flops / byte. This means that if we can make
the computation more efficient we might be able to get closer to the peak.

### Step 2

The GPP kernel has a reduction on the arrays `ssx_array` and `sch_array` (the number of reduction variables is equal to the
trip count of the iw loop, which is 2 in the current implementation -- nstart == 2, nend == 3). The baseline code has already
unrolled this loop and done the reduction over four scalars (which makes sense because at this time OpenACC does not implement
array reductions). However, this means that the kernel is doing reductions on two variables, increasing memory traffic and
involving operations like threadblock synchronizations. In this step 2 we move the innermost loop outside the kernel, so that
we run the kernel two consecutive times, reducing on the relevant variable each time. This results in a modest increase in
performance, implying that the runtime of each of the three launched kernels is less than 1/2 of the original runtime. The
arithmetic intensity decreases a bit, though the kernel is still compute bound.

### Step 3

There are a couple of points in the code that involve a double precision divide of two complex numbers. A division in complex
arithmetic is a little more involved than a division in real numbers: if `z1 = a + bi` and `z2 = c + di`, then `z1 / z2 = (ac + bd) / K +
((bc - ad) / K) i`, where `K = c^2 + d^2`; but still, we ultimately end up with a floating point divide, and if we inspect the PTX
instructions emitted for this kernel (say, with `cuobjdump -ptx ./gpp.x`) we will see `div.rn.f64` instructions emitted. Floating point
divisions are generally slow and require many cycles compared to multiplies/adds.

However, NVIDIA GPUs also have a faster reciprocal operation for double precision numbers (`rcp.rn.f64`), so we coax the compiler into
taking this path by explicitly constructing the reciprocal of the complex numbers first, and then adjusting the calculation appropriately
to use this reciprocal. Inspection of the PTX verifies that this has occurred.

Another quirk of complex math is that while the absolute value of a real number is a simple operation, the absolute value of a complex number
is given by `a + bi = sqrt(a^2 + b^2)`. This step replaces the explicit calculation of these absolute value operations, noticing that we don't
actually need them explicitly, we just need the final comparison of ssx to ssxcutoff to be valid.

This step results in a significant (~40%) speedup. Looking at the Roofline chart, we have decreased our arithmetic intensity by quite a bit,
returning to the bandwidth bound part of the chart; however, we are also a bit closer to the Roofline than when we started in the baseline.

### Step 4

At this point we have probably picked most of the low-hanging fruit. It is at this point that we can consider tuning how the parallelism
maps to the hardware (this would have been premature during an earlier step -- it's usually best to save this step for last, so that you
do not lock yourself into a particular parallel pattern that can hide other opportunities for a speedup). In OpenACC the simplest way to
do this is by controlling the vector_length parameter, which translates in CUDA to the number of threads per block. In most applications
running on NVIDIA GPUs, the best choice is empirically determined. It turns out for this kernel that 512 threads per block is a good choice.
Inspection of the Nsight Compute report shows that this is actually mostly the result of the fact that this threadblock size requires the
compiler to only use 128 registers per thread, and the increase in occupancy that results from fitting more threads per SM at once (due to
the decreased register load) evidently more than compensates from whatever inefficiencies come from using fewer registers (if any). We could
also have achieved this same effect by directly capping the register count (for the PGI compiler, use -ta=tesla:maxregcount:128).

### Next steps

At this point you should experiment with some other possible optimizations to this kernel and practice collecting the report and analyzing
it in Nsight Compute. Two potential optimizations that we recommend trying are (1) move redundant computations (ones that don't depend on
n1_loc) outside of the innermost loop and (2) cache repeated array accesses to the same index in temporary variables. Do these help? If so,
that suggests the compiler couldn't figure these optimizations out for you -- is that surprising? There are other possibilities too, such as
further modifying the kernel to use multiple levels of parallelism rather than collapsing the loops, so give it your best shot. It's OK if
you can't make the code any faster -- what matters is gaining experience thinking about performance analysis on GPUs.


# Nsight Compute Section Files

A few section files are provided in [/ncu-section-files](/ncu-section-files) where `SpeedOfLight.section` and `SpeedOfLight_RooflineChart.section` currently ship with CUDA 11, and `SpeedOfLight_HierarchicalxxxxRooflineChart.section` are the custom ones that users can copy/paste to their own directory and call Nsight Compute with. 
The default `SpeedOfLight_RooflineChart.section` covers only device memory level, while the custom ones support Roofline analysis on the L1 and L2 levels as well (hence the name `hierarchical`). 
Four different custom files are provided to cover double-precision, single-precision, half-precision, and Tensor Core operations. 
  + `/ncu-section-files/SpeedOfLight_HierarchicalDoubleRooflineChart.section`
  + `/ncu-section-files/SpeedOfLight_HierarchicalSingleRooflineChart.section`
  + `/ncu-section-files/SpeedOfLight_HierarchicalHalfRooflineChart.section` 
  + `/ncu-section-files/SpeedOfLight_HierarchicalTensorRooflineChart.section`  


# Customized ncu-based Roofline Workflow 

For tigher integration with users' other workflow, [/custom-scripts](/custom-scripts) provides a set of scripts for manual metric collection and Roofline visualization. 
  + `run.gpp.customized`
  + `postprocess.py` and `roofline.py`

The `run.gpp.customized` script uses GPP as an example to show a list of Nsight Compute metrics required for Roofline analaysis. These metrics are collected using the command-line utility of Nsight Compute `ncu` (or `nv-nsight-cu-cli`) and are written into a `.csv` file in `/custom-scripts`. 
The results are then post processed by `postprocess.py` using Pandas to calculate the Arithmetic Intensity (AI) and FLOP/s throughput for each kernel being profiled.
When processing is done, `postprocess.py` will call `roofline.py` which is based on Matplotlib, to plot Roofline charts and then save the charts into `.png` files. 

**The data collection methodology used in these scripts is detailed below. It is new from Nsight Compute in CUDA 11 so please give it a try and let us know if there is any problem.**

  - `Time`:  
    + sm__cycles_elapsed.avg / sm__cycles_elapsed.avg.per_second
  - `FLOPs`:  
    + `DP`: sm__sass_thread_inst_executed_op_dadd_pred_on.sum + 2 x sm__sass_thread_inst_executed_op_dfma_pred_on.sum + sm__sass_thread_inst_executed_op_dmul_pred_on.sum  
    + `SP`: sm__sass_thread_inst_executed_op_fadd_pred_on.sum + 2 x sm__sass_thread_inst_executed_op_ffma_pred_on.sum + sm__sass_thread_inst_executed_op_fmul_pred_on.sum  
    + `HP`: sm__sass_thread_inst_executed_op_hadd_pred_on.sum + 2 x sm__sass_thread_inst_executed_op_hfma_pred_on.sum + sm__sass_thread_inst_executed_op_hmul_pred_on.sum  
    + `Tensor Core`: 512 x sm__inst_executed_pipe_tensor.sum
  - `Bytes`:  
    + `DRAM`: dram__bytes.sum  
    + `L2`: lts__t_bytes.sum  
    + `L1`: l1tex__t_bytes.sum

**Also, please bear in mind that these scripts are written with GPP in mind, so please modify certain parameters as necessary, such as location of files, name of the output, kernels to profile, type of Roofline to use (e.g. HBM or hierarchical, and double/single/half precision), min/max of the axes of the chart, and the size/colors of the markers. Happy hacking :)**  

# RooflineAnalysis_On_NVIDIA_GPU
# RooflineAnalysis_On_NVIDIA_GPU
# RooflineAnalysis_On_NVIDIA_GPU
