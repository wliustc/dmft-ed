!+-----------------------------------------------------------------------------+!
!PURPOSE:  G0^{-1} and F0{-1} non-interacting Green's functions on the Matsubara axis:
! _1 : input type(effective_bath) dmft_bath
! _2 : input array bath
! Delta_ : normal
! Fdelta_: anomalous
!+-----------------------------------------------------------------------------+!
!NORMAL:
function invg0_bath_mats_main(x,dmft_bath_) result(G0and)
  complex(8),dimension(:),intent(in)                  :: x
  type(effective_bath)                                :: dmft_bath_
  complex(8),dimension(Nspin,Nspin,Norb,Norb,size(x)) :: G0and,Delta,Fdelta
  integer                                             :: i,iorb,jorb,ispin,jspin,io,jo,Nso,L
  real(8),dimension(size(x))                          :: det
  complex(8),dimension(size(x))                       :: fg,ff
  complex(8),dimension(:,:),allocatable               :: fgorb,zeta
  !
  G0and = zero
  !
  L=size(x)
  !
  select case(bath_type)
  case default                !normal: only _{aa} are allowed (no inter-orbital local mixing)
     !
     select case(ed_mode)
     case default
        !
        Delta = delta_bath_mats(x,dmft_bath_)
        do ispin=1,Nspin
           do iorb=1,Norb
              G0and(ispin,ispin,iorb,iorb,:) = x(:) + xmu - impHloc(ispin,ispin,iorb,iorb) - Delta(ispin,ispin,iorb,iorb,:)
           enddo
        enddo
        !
     case ("superc")
        !
        Delta =  delta_bath_mats(x,dmft_bath_)
        do ispin=1,Nspin
           do iorb=1,Norb
              G0and(ispin,ispin,iorb,iorb,:)  =  x(:) + xmu - impHloc(ispin,ispin,iorb,iorb) -  Delta(ispin,ispin,iorb,iorb,:)
           enddo
        enddo
        !
     case ("nonsu2")
        !
        Delta = delta_bath_mats(x,dmft_bath_)
        allocate(zeta(Nspin,Nspin))
        do i=1,L
           zeta  = (x(i) + xmu)*zeye(Nspin)
           do iorb=1,Norb
              do ispin=1,Nspin
                 do jspin=1,Nspin
                    G0and(ispin,jspin,iorb,iorb,i) = zeta(ispin,jspin) - impHloc(ispin,jspin,iorb,iorb) - Delta(ispin,jspin,iorb,iorb,i)
                 enddo
              enddo
           enddo
        enddo
        deallocate(zeta)
        !
     end select
     !
  case ("hybrid")             !hybrid: all _{ab} components allowed (inter-orbital local mixing present)
     !
     select case(ed_mode)
     case default
        !
        allocate(zeta(Norb,Norb))
        Delta = delta_bath_mats(x,dmft_bath_)
        do ispin=1,Nspin
           do i=1,L
              zeta = (x(i)+xmu)*zeye(Norb)
              do iorb=1,Norb
                 do jorb=1,Norb
                    G0and(ispin,ispin,iorb,jorb,i) = zeta(iorb,jorb)-impHloc(ispin,ispin,iorb,jorb)-Delta(ispin,ispin,iorb,jorb,i)
                 enddo
              enddo
           enddo
	enddo
        deallocate(zeta)
        !
     case ("superc")
        !
        allocate(zeta(2*Norb,2*Norb))
        Delta  = delta_bath_mats(x,dmft_bath_)
        Fdelta = fdelta_bath_mats(x,dmft_bath_)
        do ispin=1,Nspin
           do i=1,L
              zeta = zero
              do iorb=1,Norb
                 zeta(iorb,iorb)           = x(i) + xmu
                 zeta(iorb+Norb,iorb+Norb) = x(i) - xmu
              enddo
              do iorb=1,Norb
                 do jorb=1,Norb
                    G0and(ispin,ispin,iorb,jorb,i) = zeta(iorb,jorb) - impHloc(ispin,ispin,iorb,jorb) - Delta(ispin,ispin,iorb,jorb,i)
                 enddo
              enddo
           enddo
        enddo
        deallocate(zeta)
        !
     case ("nonsu2")
        !
        Nso=Nspin*Norb
        allocate(zeta(Nso,Nso))
        Delta = delta_bath_mats(x,dmft_bath_)
        do i=1,L
           zeta  = (x(i) + xmu)*zeye(Nso)
           do ispin=1,Nspin
              do jspin=1,Nspin
                 do iorb=1,Norb
                    do jorb=1,Norb
                       io = iorb + (ispin-1)*Norb
                       jo = jorb + (jspin-1)*Norb
                       G0and(ispin,jspin,iorb,jorb,i) = zeta(io,jo) -impHloc(ispin,jspin,iorb,jorb) - Delta(ispin,jspin,iorb,jorb,i)
                    enddo
                 enddo
              enddo
           enddo
        enddo
        deallocate(zeta)
        !
     end select
     !
  end select
  !
end function invg0_bath_mats_main


function invg0_bath_mats_ispin_jspin(ispin,jspin,x,dmft_bath_) result(G0out)
  integer,intent(in)                                  :: ispin,jspin
  complex(8),dimension(:),intent(in)                  :: x
  type(effective_bath)                                :: dmft_bath_
  complex(8),dimension(Norb,Norb,size(x))             :: G0out
  complex(8),dimension(Nspin,Nspin,Norb,Norb,size(x)) :: G0and
  G0and = invg0_bath_mats_main(x,dmft_bath_)
  G0out = G0and(ispin,jspin,:,:,:)
end function invg0_bath_mats_ispin_jspin


function invg0_bath_mats_ispin_jspin_iorb_jorb(ispin,jspin,iorb,jorb,x,dmft_bath_) result(G0out)
  integer,intent(in)                                  :: iorb,jorb,ispin,jspin
  complex(8),dimension(:),intent(in)                  :: x
  type(effective_bath)                                :: dmft_bath_
  complex(8)                                          :: G0out(size(x))
  complex(8),dimension(Nspin,Nspin,Norb,Norb,size(x)) :: G0and
  G0and = invg0_bath_mats_main(x,dmft_bath_)
  G0out = G0and(ispin,jspin,iorb,jorb,:)
end function invg0_bath_mats_ispin_jspin_iorb_jorb


function invg0_bath_mats_main_(x,bath_) result(G0and)
  complex(8),dimension(:),intent(in)                  :: x
  type(effective_bath)                                :: dmft_bath_
  complex(8),dimension(Nspin,Nspin,Norb,Norb,size(x)) :: G0and
  real(8),dimension(:)                                :: bath_
  logical                                             :: check
  check= check_bath_dimension(bath_)
  if(.not.check)stop "invg0_bath_mats_main_ error: wrong bath dimensions"
  call allocate_bath(dmft_bath_)
  call set_bath(bath_,dmft_bath_)
  G0and = invg0_bath_mats_main(x,dmft_bath_)
  call deallocate_bath(dmft_bath_)
end function invg0_bath_mats_main_

function invg0_bath_mats_ispin_jspin_(ispin,jspin,x,bath_) result(G0out)
  integer,intent(in)                      :: ispin,jspin
  complex(8),dimension(:),intent(in)      :: x
  type(effective_bath)                    :: dmft_bath_
  complex(8),dimension(Norb,Norb,size(x)) :: G0out
  real(8),dimension(:)                    :: bath_
  logical                                 :: check
  check= check_bath_dimension(bath_)
  if(.not.check)stop "invg0_bath_mats_ error: wrong bath dimensions"
  call allocate_bath(dmft_bath_)
  call set_bath(bath_,dmft_bath_)
  G0out = invg0_bath_mats_ispin_jspin(ispin,jspin,x,dmft_bath_)
  call deallocate_bath(dmft_bath_)
end function invg0_bath_mats_ispin_jspin_

function invg0_bath_mats_ispin_jspin_iorb_jorb_(ispin,jspin,iorb,jorb,x,bath_) result(G0out)
  integer,intent(in)                 :: iorb,jorb,ispin,jspin
  complex(8),dimension(:),intent(in) :: x
  type(effective_bath)               :: dmft_bath_
  complex(8)                         :: G0out(size(x))
  real(8),dimension(:)               :: bath_
  logical                            :: check
  check= check_bath_dimension(bath_)
  if(.not.check)stop "invg0_bath_mats_ error: wrong bath dimensions"
  call allocate_bath(dmft_bath_)
  call set_bath(bath_,dmft_bath_)
  G0out = invg0_bath_mats_ispin_jspin_iorb_jorb(ispin,jspin,iorb,jorb,x,dmft_bath_)
  call deallocate_bath(dmft_bath_)
end function invg0_bath_mats_ispin_jspin_iorb_jorb_










!ANOMALous:
function invf0_bath_mats_main(x,dmft_bath_) result(F0and)
  complex(8),dimension(:),intent(in)                  :: x
  type(effective_bath)                                :: dmft_bath_
  complex(8),dimension(Nspin,Nspin,Norb,Norb,size(x)) :: F0and,Fdelta
  integer                                             :: iorb,jorb,ispin,jspin,i,L
  !
  F0and=zero
  !
  L = size(x)
  !
  select case(bath_type)
  case default                !normal: only _{aa} are allowed (no inter-orbital local mixing)
     !
     select case(ed_mode)
     case default
        !
        stop "Invf0_bath_mats error: called with ed_mode=normal/nonsu2, bath_type=normal"
        !
     case ("superc")
        !
        Fdelta= fdelta_bath_mats(x,dmft_bath_)
        do ispin=1,Nspin
           do iorb=1,Norb
              F0and(ispin,ispin,iorb,iorb,:) = -Fdelta(ispin,ispin,iorb,iorb,:)
           enddo
        enddo
     end select
     !
     !
  case ("hybrid")             !hybrid: all _{ab} components allowed (inter-orbital local mixing present)
     select case(ed_mode)
     case default
        !
        stop "Invf0_bath_mats error: called with ed_mode=normal/nonsu2, bath_type=hybrid"
        !
     case ("superc")
        !
        Fdelta= fdelta_bath_mats(x,dmft_bath_)
        do ispin=1,Nspin
           do iorb=1,Norb
              do jorb=1,Norb
                 F0and(ispin,ispin,iorb,jorb,:) = -Fdelta(ispin,ispin,iorb,jorb,:)
              enddo
           enddo
        enddo
        !
     end select
     !
  end select
end function invf0_bath_mats_main

function invf0_bath_mats_ispin_jspin(ispin,jspin,x,dmft_bath_) result(F0out)
  integer,intent(in)                                  :: ispin,jspin
  complex(8),dimension(:),intent(in)                  :: x
  type(effective_bath)                                :: dmft_bath_
  complex(8),dimension(Norb,Norb,size(x))             :: F0out
  complex(8),dimension(Nspin,Nspin,Norb,Norb,size(x)) :: F0and
  F0and = Invf0_bath_mats_main(x,dmft_bath_)
  F0out = F0and(ispin,jspin,:,:,:)
end function invf0_bath_mats_ispin_jspin

function invf0_bath_mats_ispin_jspin_iorb_jorb(ispin,jspin,iorb,jorb,x,dmft_bath_) result(F0out)
  integer,intent(in)                                  :: iorb,jorb,ispin,jspin
  complex(8),dimension(:),intent(in)                  :: x
  type(effective_bath)                                :: dmft_bath_
  complex(8)                                          :: F0out(size(x))
  complex(8),dimension(Nspin,Nspin,Norb,Norb,size(x)) :: F0and
  F0and = invf0_bath_mats_main(x,dmft_bath_)
  F0out = F0and(ispin,jspin,iorb,jorb,:)
end function invf0_bath_mats_ispin_jspin_iorb_jorb

function invf0_bath_mats_main_(x,bath_) result(F0and)
  complex(8),dimension(:),intent(in)                  :: x
  type(effective_bath)                                :: dmft_bath_
  complex(8),dimension(Nspin,Nspin,Norb,Norb,size(x)) :: F0and
  real(8),dimension(:)                                :: bath_
  logical                                             :: check
  check= check_bath_dimension(bath_)
  if(.not.check)stop "invf0_bath_mats_main_ error: wrong bath dimensions"
  call allocate_bath(dmft_bath_)
  call set_bath(bath_,dmft_bath_)
  F0and = invf0_bath_mats_main(x,dmft_bath_)
  call deallocate_bath(dmft_bath_)
end function invf0_bath_mats_main_

function invf0_bath_mats_ispin_jspin_(ispin,jspin,x,bath_) result(F0out)
  integer,intent(in)                      :: ispin,jspin
  complex(8),dimension(:),intent(in)      :: x
  type(effective_bath)                    :: dmft_bath_
  complex(8),dimension(Norb,Norb,size(x)) :: F0out
  real(8),dimension(:)                    :: bath_
  logical                                 :: check
  check= check_bath_dimension(bath_)
  if(.not.check)stop "invf0_bath_mats_ispin_jspin_ error: wrong bath dimensions"
  call allocate_bath(dmft_bath_)
  call set_bath(bath_,dmft_bath_)
  F0out = invf0_bath_mats_ispin_jspin(ispin,jspin,x,dmft_bath_)
  call deallocate_bath(dmft_bath_)
end function invf0_bath_mats_ispin_jspin_

function invf0_bath_mats_ispin_jspin_iorb_jorb_(ispin,jspin,iorb,jorb,x,bath_) result(F0out)
  integer,intent(in)                 :: iorb,jorb,ispin,jspin
  complex(8),dimension(:),intent(in) :: x
  type(effective_bath)               :: dmft_bath_
  complex(8)                         :: F0out(size(x))
  real(8),dimension(:)               :: bath_
  logical                            :: check
  check= check_bath_dimension(bath_)
  if(.not.check)stop "invf0_bath_mats_ispin_jspin_iorb_jorb_ error: wrong bath dimensions"
  call allocate_bath(dmft_bath_)
  call set_bath(bath_,dmft_bath_)
  F0out = invf0_bath_mats_ispin_jspin_iorb_jorb(ispin,jspin,iorb,jorb,x,dmft_bath_)
  call deallocate_bath(dmft_bath_)
end function invf0_bath_mats_ispin_jspin_iorb_jorb_
