!+-------------------------------------------------------------+
!PURPOSE  : Chi^2 interface for Hybridized bath nonsu2 phase
!+-------------------------------------------------------------+
subroutine chi2_fitgf_hybrid_nonsu2(fg,bath_)
  complex(8),dimension(:,:,:,:,:)        :: fg ![Nspin][Nspin][Norb][Norb][Lmats]
  real(8),dimension(:),intent(inout) :: bath_
  real(8),dimension(:),allocatable   :: array_bath
  integer                            :: iter,i,j,iorb,jorb,ispin,jspin,io,jo,count,Asize
  real(8)                            :: chi
  logical                            :: check
  type(effective_bath)               :: dmft_bath
  character(len=20)                  :: suffix
  integer                            :: unit
  !
  if(size(fg,1)/=Norb)stop "chi2_fitgf_hybrid_nonsu2 error: size[fg,1]!=Nspin"
  if(size(fg,2)/=Norb)stop "chi2_fitgf_hybrid_nonsu2 error: size[fg,2]!=Nspin"
  if(size(fg,3)/=Norb)stop "chi2_fitgf_hybrid_nonsu2 error: size[fg,3]!=Norb"
  if(size(fg,4)/=Norb)stop "chi2_fitgf_hybrid_nonsu2 error: size[fg,4]!=Norb"
  !
  check= check_bath_dimension(bath_)
  if(.not.check)stop "chi2_fitgf_hybrid_nonsu2 error: wrong bath dimensions"
  !
  Ldelta = Lfit ; if(Ldelta>size(fg,5))Ldelta=size(fg,5)
  !
  totNso = Nspin*(Nspin+1)/2 * Norb*(Norb+1)/2
  allocate(getIspin(totNso),getJspin(totNso))
  allocate(getIorb(totNso),getJorb(totNso))
  count=0
  do ispin=1,Nspin
     do jspin=ispin,Nspin
        do iorb=1,Norb
           do jorb=iorb,Norb
              count=count+1
              getIspin(count) = ispin
              getIorb(count)  = iorb
              getJspin(count) = jspin
              getJorb(count)  = jorb
           enddo
        enddo
     enddo
  enddo
  if(totNso/=count)stop "chi2_fitgf_hybrid_nonsu2: error counting the spin-orbitals"
  !
  allocate(Gdelta(totNso,Ldelta))
  allocate(Xdelta(Ldelta))
  allocate(Wdelta(Ldelta))
  !
  Xdelta = pi/beta*(2*arange(1,Ldelta)-1)
  !
  select case(cg_weight)
  case default
     Wdelta=1d0*Ldelta
  case(1)
     Wdelta=1d0
  case(2)
     Wdelta=1d0*arange(1,Ldelta)
  case(3)
     Wdelta=Xdelta
  end select
  !
  call allocate_bath(dmft_bath)
  call set_bath(bath_,dmft_bath)
  !
  call allocate_bath(chi2_bath)
  call set_bath(bath_,chi2_bath)
  !
  Asize = get_chi2_bath_size()
  allocate(array_bath(Asize))
  !
  do i=1,totNso
     Gdelta(i,1:Ldelta) = fg(getIspin(i),getJspin(i),getIorb(i),getJorb(i),1:Ldelta)
  enddo
  !
  call dmft_bath2chi2_bath(dmft_bath,array_bath)
  !
  select case(cg_method)     !0=NR-CG[default]; 1=CG-MINIMIZE; 2=CG+
  case default
     select case (cg_scheme)
     case ("weiss")
        call fmin_cg(array_bath,&
             chi2_weiss_hybrid_nonsu2,&
             iter,chi,&
             itmax=cg_niter,&
             ftol=cg_Ftol  ,&
             istop=cg_stop ,&
             eps=cg_eps)
     case ("delta")
        call fmin_cg(array_bath,&
             chi2_delta_hybrid_nonsu2,&
             grad_chi2_delta_hybrid_nonsu2,&
             iter,chi,&
             itmax=cg_niter,&
             ftol=cg_Ftol  ,&
             istop=cg_stop ,&
             eps=cg_eps)
     case default
        stop "chi2_fitgf_hybrid_nonsu2 error: cg_scheme != [weiss,delta]"
     end select
     !
  case (1)
     select case (cg_scheme)
     case ("weiss")
        call fmin_cgminimize(array_bath,&
             chi2_weiss_hybrid_nonsu2,&
             iter,chi,&
             itmax=cg_niter,&
             ftol=cg_Ftol)
     case ("delta")
        call fmin_cgminimize(array_bath,&
             chi2_delta_hybrid_nonsu2,&
             iter,chi,&
             itmax=cg_niter,&
             ftol=cg_Ftol)
     case default
        stop "chi2_fitgf_hybrid_nonsu2 error: cg_scheme != [weiss,delta]"
     end select
     !
  case (2)
     select case (cg_scheme)
     case ("weiss")
        call fmin_cgplus(array_bath,&
             chi2_weiss_hybrid_nonsu2,&
             iter,chi,&
             itmax=cg_niter,&
             ftol=cg_Ftol)
     case ("delta")
        call fmin_cgplus(array_bath,&
             chi2_delta_hybrid_nonsu2,&
             grad_chi2_delta_hybrid_nonsu2,&
             iter,chi,&
             itmax=cg_niter,&
             ftol=cg_Ftol)
     case default
        stop "chi2_fitgf_hybrid_nonsu2 error: cg_scheme != [weiss,delta]"
     end select
     !
  end select
  !
  !
  if(ed_verbose<5)write(LOGfile,"(A,ES18.9,A,I5,A)")&
       "chi^2|iter"//reg(ed_file_suffix)//'= ',chi," | ",iter,&
       "  <--  All Orbs, All Spins"
  !
  if(ed_verbose<2)then
     suffix="_ALLorb_ALLspins"//reg(ed_file_suffix)
     unit=free_unit()
     open(unit,file="chi2fit_results"//reg(suffix)//".ed",position="append")
     write(unit,"(ES18.9,1x,I5)") chi,iter
     close(unit)
  endif
  !
  call chi2_bath2dmft_bath(array_bath,dmft_bath)
  !
  if(ed_verbose<2)call write_bath(dmft_bath,LOGfile)
  !
  call save_bath(dmft_bath)
  !
  if(ed_verbose<3)call write_fit_result(ispin)
  !
  call copy_bath(dmft_bath,bath_)
  call deallocate_bath(dmft_bath)
  deallocate(Gdelta,Xdelta,Wdelta)
  deallocate(getIspin,getJspin)
  deallocate(getIorb,getJorb)
  !
contains
  !
  subroutine write_fit_result(ispin)
    complex(8)        :: fgand(Nspin,Nspin,Norb,Norb,Ldelta)
    integer           :: i,j,s,l,iorb,jorb,ispin,jspin
    real(8)           :: w
    do i=1,Ldelta
       w=Xdelta(i)
       if(cg_scheme=='weiss')then
          fgand(:,:,:,:,i) = g0and_bath_mats(xi*w,dmft_bath)
       else
          fgand(:,:,:,:,i) = delta_bath_mats(xi*w,dmft_bath)
       endif
    enddo
    !
    do l=1,totNso
       iorb = getIorb(l)
       jorb = getJorb(l)
       ispin = getIspin(l)
       jspin = getJspin(l)
       suffix="_l"//reg(txtfy(iorb))//&
            "_m"//reg(txtfy(jorb))//&
            "_s"//reg(txtfy(ispin))//&
            "_r"//reg(txtfy(jspin))//reg(ed_file_suffix)
       unit=free_unit()
       open(unit,file="fit_delta"//reg(suffix)//".ed")
       do i=1,Ldelta
          w = Xdelta(i)
          write(unit,"(5F24.15)")Xdelta(i),&
               dimag(fg(ispin,jspin,iorb,jorb,i)),dimag(fgand(ispin,jspin,iorb,jorb,i)),&
               dreal(fg(ispin,jspin,iorb,jorb,i)),dreal(fgand(ispin,jspin,iorb,jorb,i))
       enddo
       close(unit)       
    enddo
  end subroutine write_fit_result
  
end subroutine chi2_fitgf_hybrid_nonsu2







!+-------------------------------------------------------------+
!PURPOSE: Evaluate the \chi^2 distance of \Delta_Anderson function.
!+-------------------------------------------------------------+
function chi2_delta_hybrid_nonsu2(a) result(chi2)
  real(8),dimension(:)                               ::  a
  real(8),dimension(totNspin)                        ::  chi2_spin
  complex(8),dimension(Nspin,Nspin,Norb,Norb,Ldelta) ::  g0
  real(8)                                            ::  chi2
  real(8)                                            ::  w
  integer                                            ::  i,l,iorb,jorb,ispin,jspin
  !
  call chi2_bath2dmft_bath(a,chi2_bath)
  !
  do i=1,Ldelta
     w = xdelta(i)
     g0(:,:,:,:,i) = delta_bath_mats(xi*w,chi2_bath)
  enddo
  !
  do l=1,totNso
     iorb = getIorb(l)
     jorb = getJorb(l)
     ispin = getIspin(l)
     jspin = getJspin(l)
     chi2_spin(l) = sum(abs(Gdelta(l,:)-g0(ispin,jspin,iorb,jorb,:))**2/Wdelta(:))
  enddo
  !
  chi2=sum(chi2_spin)
  !
end function chi2_delta_hybrid_nonsu2


!+-------------------------------------------------------------+
!PURPOSE: Evaluate the gradient \Grad\chi^2 of 
! \Delta_Anderson function.
!+-------------------------------------------------------------+
function grad_chi2_delta_hybrid_nonsu2(a) result(dchi2)
  real(8),dimension(:)                                       :: a
  real(8),dimension(size(a))                                 :: dchi2
  real(8),dimension(totNorb,size(a))                         :: df
  complex(8),dimension(Nspin,Nspin,Norb,Norb,Ldelta)         :: g0
  complex(8),dimension(Nspin,Nspin,Norb,Norb,Ldelta,size(a)) :: dg0
  integer                                                    :: i,j,l,iorb,jorb,ispin,jspin
  real(8)                                                    :: w
  !
  call chi2_bath2dmft_bath(a,chi2_bath)
  !
  do i=1,Ldelta
     w        = Xdelta(i)
     g0(:,:,:,:,i)    = delta_bath_mats(xi*w,chi2_bath)
     dg0(:,:,:,:,i,:) = grad_delta_bath_mats(xi*w,chi2_bath,size(a))
  enddo
  !
  do l=1,totNso
     iorb = getIorb(l)
     jorb = getJorb(l)
     ispin = getIspin(l)
     jspin = getJspin(l)
     do j=1,size(a)
        df(l,j)=&
             sum( dreal(Gdelta(l,:)-g0(ispin,jspin,iorb,jorb,:))*dreal(dg0(ispin,jspin,iorb,jorb,:,j))/Wdelta(:) ) + &
             sum( dimag(Gdelta(l,:)-g0(ispin,jspin,iorb,jorb,:))*dimag(dg0(ispin,jspin,iorb,jorb,:,j))/Wdelta(:) )
     enddo
  enddo
  !
  dchi2 = -2.d0*sum(df,1)     !sum over all spin-spin indices
  !
end function grad_chi2_delta_hybrid_nonsu2


!+-------------------------------------------------------------+
!PURPOSE: Evaluate the \chi^2 distance of G_0_Anderson function 
! The Gradient is not evaluated, so the minimization requires 
! a numerical estimate of the gradient. 
!+-------------------------------------------------------------+
function chi2_weiss_hybrid_nonsu2(a) result(chi2)
  real(8),dimension(:)                               :: a
  real(8),dimension(totNspin)                        :: chi2_spin
  complex(8),dimension(Nspin,Nspin,Norb,Norb,Ldelta) :: g0
  real(8)                                            :: chi2
  real(8)                                            :: w
  integer                                            :: i,l,iorb,jorb,ispin,jspin
  !
  call chi2_bath2dmft_bath(a,chi2_bath,iorb=iorb)
  !
  do i=1,Ldelta
     w = xdelta(i)
     g0(:,:,:,:,i) = g0and_bath_mats(xi*w,chi2_bath)
  enddo
  !
  do l=1,totNso
     iorb = getIorb(l)
     jorb = getJorb(l)
     ispin = getIspin(l)
     jspin = getJspin(l)
     chi2_spin(l) = sum(abs(Gdelta(l,:)-g0(ispin,jspin,iorb,jorb,:))**2/Wdelta(:))
  enddo
  !
  chi2=sum(chi2_spin)
  !
end function chi2_weiss_hybrid_nonsu2

