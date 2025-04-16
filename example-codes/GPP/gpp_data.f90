
module sigma_gpp_data_module

  implicit none

  integer, parameter :: DP = kind(1.0d0)
  integer, parameter :: DPC = kind((1.0d0,1.0d0))

  integer, allocatable :: indinv(:)
  real(DP), allocatable :: vcoul(:) !< (ncoul)
  integer, allocatable :: inv_igp_index(:) !< (neps)
  complex(DPC), allocatable :: aqsntemp(:,:), aqsmtemp(:,:)
  complex(DPC), allocatable :: asxtemp(:), achtemp(:)
  complex(DPC), allocatable :: asxtempref(:),achtempref(:)
  complex(DPC), allocatable :: I_eps_array(:,:)
  complex(DPC), allocatable :: wtilde_array(:,:)
  complex(DPC), allocatable :: aqsmtemp_local(:,:)
  real(DP), allocatable :: occ_array(:)
  real(DP), allocatable :: wx_array_t(:,:)
  integer, allocatable :: n1true_array(:)
  real(DP), allocatable :: vcoul_loc(:)
  integer, allocatable :: peinf_indext_dist(:)
  real(DP), allocatable :: wfnkq_ekq(:)

  real(DP) :: limitone, limittwo
  integer :: ipe, ispin, ngpown, ncouls, nstart, nend, sig_fdf, n1true, indigp
  integer :: peinf_ntband_dist, gvec_ng, ncoul, epsmpi_ngpown_max, peinf_ntband_max, sig_ntband
  real(DP) :: sig_gamma, e_lk, sig_dw
  integer :: nvband, ncrit
  integer :: ntband_dist
  real(DP) :: efermi, tol, sexcut

  real(DP), parameter :: TOL_Small = 1.0d-6
  real(DP), parameter :: TOL_Zero = 1.0d-12

contains

  subroutine initialize_data ()

    implicit none

    integer(kind=8) :: n1_loc, my_igp
    real(DP) :: e_n1kq
    integer :: iw, igp

    open(unit=66, file='gpp214unformatted.dat', status='old', form='unformatted')
    read(unit=66) sig_ntband,gvec_ng,ncoul,epsmpi_ngpown_max,peinf_ntband_max
    read(unit=66) peinf_ntband_dist,ipe,ispin,ngpown,ncouls
    
    allocate(peinf_indext_dist(peinf_ntband_max))
    allocate(wfnkq_ekq(sig_ntband))
    allocate(inv_igp_index(epsmpi_ngpown_max)) !< (neps)
    allocate(indinv(gvec_ng))
    allocate(aqsmtemp(ncouls,peinf_ntband_max))
    allocate(vcoul(ncoul))
    allocate(wtilde_array(ncouls,ngpown))
    allocate(I_eps_array(ncouls,ngpown))
    allocate(aqsntemp(ncouls,peinf_ntband_max))
    allocate(asxtemp(3))
    allocate(achtemp(3))
    allocate(asxtempref(3))
    allocate(achtempref(3))
    
    if (size(peinf_indext_dist) .ne. peinf_ntband_max .or. &
         size(wfnkq_ekq) .ne. sig_ntband .or. &
         size(inv_igp_index) .ne. epsmpi_ngpown_max .or. &
         size(indinv) .ne. gvec_ng .or. &
         size(aqsmtemp) .ne. (ncouls*peinf_ntband_max) .or. &
         size(vcoul) .ne. ncoul .or. &
         size(wtilde_array) .ne. (ncouls*ngpown) .or. &
         size(I_eps_array) .ne. (ncouls*ngpown) .or. &
         size(aqsntemp) .ne. (ncouls*peinf_ntband_max)) then
       write(6,*) 'Error in reading'
    endif

    read(unit=66) peinf_indext_dist(:)
    read(unit=66) wfnkq_ekq(:)
    read(unit=66) nstart,nend,sig_fdf,sig_dw,sig_gamma,e_lk
    read(unit=66) inv_igp_index(:)
    read(unit=66) gvec_ng,indinv(:)
    read(unit=66) aqsmtemp(:,:)
    read(unit=66) nvband,tol,efermi
    read(unit=66) vcoul(:)
    read(unit=66) sexcut,limittwo,limitone
    read(unit=66) wtilde_array(:,:)
    read(unit=66) I_eps_array(:,:)
    read(unit=66) aqsntemp(:,:)
    read(unit=66) asxtemp(:)
    read(unit=66) achtemp(:)
    read(unit=66) asxtempref(:)
    read(unit=66) achtempref(:)
    close(unit=66)

    allocate(wx_array_t(3,peinf_ntband_dist))

    allocate(aqsmtemp_local(ngpown,peinf_ntband_dist))
    aqsmtemp_local = (0.0d0,0.0d0)
    
    ! Some constants used in the loop below, computed here to save
    ! floating point operations
    limitone = 1D0 / (TOL_Small * 4D0)
    limittwo = sig_gamma**2

    do n1_loc = 1, peinf_ntband_dist !(ipe)
       ! n1true = "True" band index of the band n1 w.r.t. all bands
       n1true = peinf_indext_dist(n1_loc) !,ipe) ! changed to input
       ! energy of the |n1,k-q> state
       e_n1kq = wfnkq_ekq(n1true) !,ispin)
       do iw=nstart,nend
          wx_array_t(iw,n1_loc) = e_lk + sig_dw*(iw-2) - e_n1kq
          if (abs(wx_array_t(iw,n1_loc)) .lt. TOL_Zero) wx_array_t(iw,n1_loc) = TOL_Zero
       enddo

       ! fill the aqsmtemp_local array
       do my_igp = 1,  ngpown
          indigp = inv_igp_index(my_igp)
          igp = indinv(indigp)
          if (igp .le. ncouls .and. igp .gt. 0) then
             aqsmtemp_local(my_igp,n1_loc) = aqsmtemp(igp,n1_loc)
          end if
       end do
    enddo

    ntband_dist = peinf_ntband_dist !(ipe)

    allocate(n1true_array(ntband_dist))
    allocate(occ_array(ntband_dist))

    do n1_loc = 1, ntband_dist
       n1true_array(n1_loc) = peinf_indext_dist(n1_loc) !,ipe)
       e_n1kq = wfnkq_ekq(n1true_array(n1_loc)) !,ispin)
       occ_array(n1_loc) = 0.0d0
       if (peinf_indext_dist(n1_loc) .le. nvband) then
          if (abs(e_n1kq-efermi)<tol) then
             occ_array(n1_loc) = 0.5d0 ! Fermi-Dirac distribution = 1/2 at Fermi level
          else
             occ_array(n1_loc) = 1.0d0
          endif
       endif
    enddo

    allocate(vcoul_loc(ngpown))
    vcoul_loc = 0.0_dp
    do my_igp = 1,  ngpown
       indigp = inv_igp_index(my_igp)
       igp = indinv(indigp)
       if (igp <= ncouls .and. igp > 0) then
          vcoul_loc(my_igp) = vcoul(igp)
       end if
    end do

  end subroutine initialize_data


  subroutine finalize_data ()

    implicit none

    deallocate(wx_array_t)
    deallocate(n1true_array)
    deallocate(vcoul_loc)
    deallocate(aqsmtemp_local)
    deallocate(peinf_indext_dist)
    deallocate(wfnkq_ekq)
    deallocate(inv_igp_index)
    deallocate(indinv)
    deallocate(aqsmtemp)
    deallocate(vcoul)
    deallocate(wtilde_array)
    deallocate(asxtemp)
    deallocate(achtemp)
    deallocate(asxtempref)
    deallocate(achtempref)
    deallocate(I_eps_array)
    deallocate(aqsntemp)

  end subroutine finalize_data

end module sigma_gpp_data_module
