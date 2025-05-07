
program sigma_gpp_gpu 

  use sigma_gpp_data_module

  implicit none

  integer :: igp, iw
  integer(kind=8) :: my_igp, n1_loc, ig
  complex(DPC) :: Omega2, wtilde2, wtilde, delw, wdiff, cden
  complex(DPC) :: ssx_array, sch_array
!  complex(DPC) :: ssx_array_2, ssx_array_3, sch_array_2, sch_array_3
  complex(DPC) :: ssx, sch, schtt, matngmatmgp
  real(DP) :: delwr, delw2, wdiffr, rden, ssxcutoff
  real :: start, finish
  integer :: n1loc_blksize, n1loc_blk
  integer :: ig_blksize, ig_blk

  call setvbuf3f(6,2,0)

  call initialize_data()

  write(*,*) 'nstart,nend',nstart,nend
  write(*,*) 'ngpown,ncouls,ntband_dist',ngpown,ncouls,ntband_dist

  !$ACC DATA COPYIN(n1true_array,occ_array,wx_array_t,aqsmtemp_local,vcoul_loc,wtilde_array,I_eps_array,aqsntemp)

  call cpu_time(start)

  ! Write out to scalars since OpenACC does not currently support array reduction.

  ig_blksize = 128 !256
  n1loc_blksize = 64 !80 !64 !ntband_dist !16
  do iw = nstart, nend ! 2

     ssx_array = (0.0d0,0.0d0)
     sch_array = (0.0d0,0.0d0)

  !$ACC PARALLEL PRESENT(I_eps_array, aqsntemp) vector_length(32)
  !$ACC LOOP GANG VECTOR reduction(+:ssx_array,sch_array) collapse(3)
     do n1loc_blk = 1, n1loc_blksize
     do igp = 1, ngpown ! O(1000)
        do ig_blk = 1, ig_blksize

        !$ACC LOOP SEQ
        do ig = ig_blk, ncouls, ig_blksize
           !$ACC LOOP SEQ
           do n1_loc = n1loc_blk, ntband_dist, n1loc_blksize

              wtilde = wtilde_array(ig,igp)
              wtilde2 = wtilde**2
              Omega2 = wtilde2 * I_eps_array(ig,igp)

              wdiff = wx_array_t(n1_loc,iw) - wtilde
              wdiffr = wdiff * CONJG(wdiff)

              rden = 1.0d0 / wdiffr
              delw = wtilde * CONJG(wdiff) * rden
              delwr = delw * CONJG(delw)

              sch = 0.0d0
              ssx = 0.0d0
              if (wdiffr > limittwo .and. delwr < limitone) then
                 sch = delw * I_eps_array(ig,igp)
                 cden = wx_array_t(n1_loc,iw)**2 - wtilde2
                 rden = cden * CONJG(cden)
                 rden = 1.0d0 / rden
                 ssx = Omega2 * CONJG(cden) * rden
              else if (delwr > TOL_Zero) then
                 cden = (4.0d0 * wtilde2 * (delw + 0.5D0 ))
                 rden = cden * CONJG(cden)
                 rden = 1.0d0 / rden
                 ssx = -Omega2 * delw * CONJG(cden) * rden
              endif

              matngmatmgp = conjg(aqsmtemp_local(n1_loc,igp)) * aqsntemp(ig,n1_loc)

              ssxcutoff = sexcut**2 * I_eps_array(ig,igp) * CONJG(I_eps_array(ig,igp))
              rden = ssx * CONJG(ssx)
              if (rden .gt. ssxcutoff .and. wx_array_t(n1_loc,iw) .lt. 0.0d0) ssx=0.0d0


              ssx_array = ssx_array + vcoul_loc(igp) * occ_array(n1_loc) * ssx * matngmatmgp
              sch_array = sch_array + vcoul_loc(igp) * sch * matngmatmgp * 0.5d0

        enddo ! n1_loc
     enddo ! ig
     enddo ! ig_blk
  enddo ! igp
  enddo ! n1loc_blk
  !$ACC END PARALLEL

     asxtemp(iw) = asxtemp(iw) - ssx_array
     achtemp(iw) = achtemp(iw) + sch_array
end do ! iw

  call cpu_time(finish)

  print '("Time = ",f7.3," seconds.")', finish - start

  !$ACC END DATA


  if ((abs(asxtempref(nstart) - asxtemp(nstart)) + abs(asxtempref(nend) - asxtemp(nend))) < TOL_Zero) then
     write(6,*) 'asxtemp correct!'
  else
     write(6,*) 'asxtemp incorrect :-('
  endif

  if ((abs(achtempref(nstart) - achtemp(nstart)) + abs(achtempref(nend) - achtemp(nend))) < TOL_Zero) then
     write(6,*) 'achtemp correct!'
  else
     write(6,*) 'achtmp incorrect :-('
  endif

  call finalize_data()

end program sigma_gpp_gpu
