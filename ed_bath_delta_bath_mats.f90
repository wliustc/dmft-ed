!+-----------------------------------------------------------------------------+!
!PURPOSE:  Delta and Fdelta functions on the Matsubara axis:
! _1 : input type(effective_bath) dmft_bath
! _2 : input array bath
! Delta_ : normal
! Fdelta_: anomalous
!+-----------------------------------------------------------------------------+!
!NORMAL:
function delta_bath_mats_1(ispin,jspin,iorb,jorb,x,dmft_bath_) result(fg)
  integer,intent(in)                      :: iorb,jorb,ispin,jspin
  type(effective_bath)                    :: dmft_bath_
  integer                                 :: i,j,l,k
  complex(8),intent(in)                   :: x
  complex(8)                              :: fg
  real(8),dimension(Nbath)                :: eps,dps,vps,den
  real(8),dimension(Norb,Nbath)           :: vops
  select case(bath_type)
  case default                !normal: only _{aa} are allowed (no inter-orbital local mixing)
     !
     select case(ed_mode)
     case default
        eps = dmft_bath_%e(ispin,iorb,1:Nbath)
        vps = dmft_bath_%v(ispin,iorb,1:Nbath)
        !\Delta_{aa} = \sum_k [ V_{a}(k) * V_{a}(k)/(iw_n - E_{a}(k)) ]
        fg = sum( vps(:)*vps(:)/(x - eps(:)) )
        !
     case ("superc")
        eps = dmft_bath_%e(ispin,iorb,1:Nbath)
        dps = dmft_bath_%d(ispin,iorb,1:Nbath)
        vps = dmft_bath_%v(ispin,iorb,1:Nbath)
        ! Den(k) = (w_n**2 + E_{a}(k)**2 + \D_{a}(k)**2
        forall(k=1:Nbath)den(k) = dimag(x)**2 + eps(k)**2 + dps(k)**2
        !\Delta_{aa} = - \sum_k [ V_{a}(k) * V_{a}(k) * (iw_n + E_{a}(k)) / Den(k) ]
        fg = -sum( vps(:)*vps(:)*(x + eps(:))/den(:) )
        !
     end select
     !
  case ("hybrid")             !hybrid: all _{ab} components allowed (inter-orbital local mixing present)
     !
     select case(ed_mode)
     case default
        eps  = dmft_bath_%e(ispin,1     ,1:Nbath)
        vops = dmft_bath_%v(ispin,1:Norb,1:Nbath)
        !\Delta_{ab} = \sum_k [ V_{a}(k) * V_{b}(k)/(iw_n - E(k)) ]
        fg = sum( vops(iorb,:)*vops(jorb,:)/(x - eps(:)) )
        !
     case ("superc")
        eps  = dmft_bath_%e(ispin,1      ,1:Nbath)
        dps  = dmft_bath_%d(ispin,1      ,1:Nbath)
        vops = dmft_bath_%v(ispin,1:Norb,1:Nbath)
        ! Den(k) = (w_n**2 + E(k)**2 + \D(k)**2
        forall(k=1:Nbath)den(k) = dimag(x)**2 + eps(k)**2 + dps(k)**2
        !\Delta_{ab} = - \sum_k [ V_{a}(k) * V_{b}(k) * (iw_n + E(k)) / Den(k) ]
        fg = -sum( vops(iorb,:)*vops(jorb,:)*(x + eps(:))/den(:) )
        !
     end select
     !
  end select
end function delta_bath_mats_1

function delta_bath_mats_2(ispin,jspin,iorb,jorb,x,bath_) result(fg)
  integer,intent(in)    :: iorb,jorb,ispin,jspin
  type(effective_bath)  :: dmft_bath_
  complex(8),intent(in) :: x
  complex(8)            :: fg
  real(8),dimension(:)  :: bath_
  logical               :: check
  check= check_bath_dimension(bath_)
  if(.not.check)stop "delta_bath_mats_ error: wrong bath dimensions"
  call allocate_bath(dmft_bath_)
  call set_bath(bath_,dmft_bath_)
  fg = delta_bath_mats_1(ispin,jspin,iorb,jorb,x,dmft_bath_)
  call deallocate_bath(dmft_bath_)
end function delta_bath_mats_2


!ANOMALous:
function fdelta_bath_mats_1(ispin,jspin,iorb,jorb,x,dmft_bath_) result(fg)
  type(effective_bath)          :: dmft_bath_
  complex(8),intent(in)         :: x
  integer,intent(in)            :: iorb,ispin,jorb,jspin
  complex(8)                    :: fg
  real(8),dimension(Norb,Norb)  :: delta_orb
  real(8),dimension(Nbath)      :: eps,dps,vps,den
  real(8),dimension(Norb,Nbath) :: vops
  integer                       :: k
  select case(bath_type)
  case default                !normal: only _{aa} are allowed (no inter-orbital local mixing)
     !
     select case(ed_mode)
     case default
        stop "Fdelta_bath_mats error: called with ed_mode=normal, bath_type=normal"
        !
     case ("superc")
        eps = dmft_bath_%e(ispin,iorb,1:Nbath)
        dps = dmft_bath_%d(ispin,iorb,1:Nbath)
        vps = dmft_bath_%v(ispin,iorb,1:Nbath)
        ! Den(k) = (w_n**2 + E_{a}(k)**2 + \D_{a}(k)**2
        forall(k=1:Nbath)den(k) = dimag(x)**2 + eps(k)**2 + dps(k)**2
        !\FDelta_{aa} = \sum_k [ \Delta_{a}(k) * V_{a}(k) * V_{a}(k)  / Den(k) ]
        fg = sum( dps(:)*vps(:)*vps(:)/den(:) )
        !
     end select
     !
  case ("hybrid")             !hybrid: all _{ab} components allowed (inter-orbital local mixing present)
     !
     select case(ed_mode)
     case default
        stop "Fdelta_bath_mats error: called with ed_mode=normal, bath_type=hybrid"
        !
     case ("superc")
        eps  = dmft_bath_%e(ispin,1     ,1:Nbath)
        dps  = dmft_bath_%d(ispin,1     ,1:Nbath)
        vops = dmft_bath_%v(ispin,1:Norb,1:Nbath)
        ! Den(k) = (w_n**2 + E_{a}(k)**2 + \D_{a}(k)**2
        forall(k=1:Nbath)den(k) = dimag(x)**2 + eps(k)**2 + dps(k)**2
        !\FDelta_{ab} = - \sum_k [ \Delta(k) * V_{a}(k) * V_{b}(k) / Den(k) ]
        fg = -sum( dps(:)*vops(iorb,:)*vops(jorb,:)/den(:) )
        !
     end select
  end select
end function fdelta_bath_mats_1

function fdelta_bath_mats_2(ispin,jspin,iorb,jorb,x,bath_) result(fg)
  type(effective_bath)  :: dmft_bath_
  complex(8),intent(in) :: x
  integer,intent(in)    :: iorb,ispin,jorb,jspin
  complex(8)            :: fg
  real(8),dimension(:)  :: bath_
  logical               :: check
  check= check_bath_dimension(bath_)
  if(.not.check)stop "delta_bath_mats_ error: wrong bath dimensions"
  call allocate_bath(dmft_bath_)
  call set_bath(bath_,dmft_bath_)
  fg = fdelta_bath_mats_1(ispin,jspin,iorb,jorb,x,dmft_bath_)
  call deallocate_bath(dmft_bath_)
end function fdelta_bath_mats_2
