FC = nvfortran
FLAGS = -acc -gpu=cc89 -Minfo=accel -fast -Mfree -mp -Mlarge_arrays

gpp.x: gpp_data.f90 gpp.f90
	$(FC) $(FLAGS) gpp_data.f90 gpp.f90 -o gpp.x

clean:
	rm -f *.o *.mod gpp.x
