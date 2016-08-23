module ED_MAIN
  USE ED_INPUT_VARS
  USE ED_VARS_GLOBAL
  USE ED_EIGENSPACE, only: state_list,es_delete_espace
  USE ED_AUX_FUNX
  USE ED_SETUP
  USE ED_BATH_DMFT
  USE ED_BATH_USER
  USE ED_HAMILTONIAN
  USE ED_GREENS_FUNCTIONS
  USE ED_OBSERVABLES
  USE ED_ENERGY
  USE ED_DIAG
  USE SF_LINALG
  USE SF_ARRAYS, only: linspace,arange
  USE SF_IOTOOLS, only: reg,store_data,txtfy,free_unit
  USE SF_TIMER,only: start_timer,stop_timer
#ifdef _MPI
  USE SF_MPI
#endif
  implicit none
  private


  interface ed_init_solver
     module procedure :: ed_init_solver_single
     module procedure :: ed_init_solver_lattice
  end interface ed_init_solver


  interface ed_solve
     module procedure :: ed_solve_single
     module procedure :: ed_solve_lattice
  end interface ed_solve

  interface ed_rebuild_sigma
     module procedure :: ed_rebuild_sigma_single
     module procedure :: ed_rebuild_sigma_lattice
  end interface ed_rebuild_sigma

  public :: ed_init_solver
  public :: ed_solve
  public :: ed_rebuild_sigma



  real(8),dimension(:,:),allocatable,save            :: nii,dii,mii,pii,ddii,eii ![Nlat][Norb/4]
  complex(8),dimension(:,:,:,:,:,:),allocatable,save :: Smatsii,Srealii          ![Nlat][Nspin][Nspin][Norb][Norb][L]
  complex(8),dimension(:,:,:,:,:,:),allocatable,save :: SAmatsii,SArealii        ![Nlat][Nspin][Nspin][Norb][Norb][L]
  complex(8),dimension(:,:,:,:,:,:),allocatable,save :: Gmatsii,Grealii          ![Nlat][Nspin][Nspin][Norb][Norb][L]
  complex(8),dimension(:,:,:,:,:,:),allocatable,save :: Fmatsii,Frealii          ![Nlat][Nspin][Nspin][Norb][Norb][L]
  integer,allocatable,dimension(:,:)                 :: neigen_sectorii          ![Nlat][Nsectors]
  integer,allocatable,dimension(:)                   :: neigen_totalii           ![Nlat]
  real(8),dimension(:),allocatable                   :: wr,wm
  character(len=64)                                  :: suffix

contains



  !+-----------------------------------------------------------------------------+!
  ! PURPOSE: allocate and initialize one or multiple baths
  !
  ! MPI communicator is passed here just for safety reasons. Although the
  ! operations performed here are all independent (do not require MPI)
  ! these precedes the call to the ed_solver, so knowledge of the communicator
  ! is important to avoid over-printing.
  !+-----------------------------------------------------------------------------+!
#ifdef _MPI
#define INPUT_LIST MpiComm,bath,hwband,Hunit
#else
#define INPUT_LIST bath,hwband,Hunit
#endif
  subroutine ed_init_solver_single(INPUT_LIST)
#ifdef _MPI
    integer                              :: MpiComm
#endif
    real(8),dimension(:),intent(inout)   :: bath
    real(8),optional,intent(in)          :: hwband
    real(8)                              :: hwband_
    character(len=*),optional,intent(in) :: Hunit
    character(len=64)                    :: Hunit_
    logical                              :: check 
    logical,save                         :: isetup=.true.
#ifdef _MPI
    ED_MPI_COMM   = MpiComm
    ED_MPI_ID     = MPI_Get_Rank(ED_MPI_COMM)
    ED_MPI_SIZE   = MPI_Get_Size(ED_MPI_COMM)
    ED_MPI_MASTER = MPI_Get_Master(ED_MPI_COMM)
#endif
    hwband_=2.d0;if(present(hwband))hwband_=hwband
    Hunit_='inputHLOC.in';if(present(Hunit))Hunit_=Hunit
    if(ed_verbose<2.AND.ED_MPI_MASTER)write(LOGfile,"(A)")"INIT SOLVER FOR "//trim(ed_file_suffix)
    if(isetup)call init_ed_structure(Hunit_)
    bath = 0.d0
    check = check_bath_dimension(bath)
    if(.not.check)stop "init_ed_solver: wrong bath dimensions"
    call allocate_dmft_bath(dmft_bath)
    call init_dmft_bath(dmft_bath,hwband_)
    call get_dmft_bath(dmft_bath,bath)
    if(isetup)then
       select case(ed_mode)
       case default
          call setup_pointers_normal
       case ("superc")
          call setup_pointers_superc
       case ("nonsu2")
          call setup_pointers_nonsu2
       end select
    endif
    call deallocate_dmft_bath(dmft_bath)
    isetup=.false.
  end subroutine ed_init_solver_single
  !
  subroutine ed_init_solver_lattice(INPUT_LIST)
#ifdef _MPI
    integer                              :: MpiComm
#endif
    real(8),dimension(:,:)               :: bath ![Nlat][:]
    real(8),optional,intent(in)          :: hwband
    real(8)                              :: hwband_
    character(len=*),optional,intent(in) :: Hunit
    character(len=64)                    :: Hunit_
    integer                              :: ilat,Nineq,Nsect
    logical                              :: check_dim
    character(len=5)                     :: tmp_suffix
#ifdef _MPI
    ED_MPI_COMM   = MpiComm
    ED_MPI_ID     = MPI_Get_Rank(ED_MPI_COMM)
    ED_MPI_SIZE   = MPI_Get_Size(ED_MPI_COMM)
    ED_MPI_MASTER = MPI_Get_Master(ED_MPI_COMM)
#endif
    hwband_=2.d0;if(present(hwband))hwband_=hwband
    Hunit_='inputHLOC.in';if(present(Hunit))Hunit_=Hunit
    Nineq = size(bath,1)
    if(Nineq > Nlat)stop "init_lattice_bath error: size[bath,1] > Nlat"
    call setup_ed_dimensions() ! < Nsectors
    if(allocated(neigen_sectorii))deallocate(neigen_sectorii)
    if(allocated(neigen_totalii))deallocate(neigen_totalii)
    allocate(neigen_sectorii(Nineq,Nsectors))
    allocate(neigen_totalii(Nineq))
    do ilat=1,Nineq
       check_dim = check_bath_dimension(bath(ilat,:))
       if(.not.check_dim) stop "init_lattice_bath: wrong bath size dimension 1 or 2 "
       ed_file_suffix="_site"//reg(txtfy(ilat,Npad=4))
#ifdef _MPI
       call ed_init_solver_single(MpiComm,bath(ilat,:),hwband_,Hunit_)
#else
       call ed_init_solver_single(bath(ilat,:),hwband_,Hunit_)
#endif
       neigen_sectorii(ilat,:) = neigen_sector(:)
       neigen_totalii(ilat)    = lanc_nstates_total
    end do
    ed_file_suffix=""
#ifdef _MPI
    call MPI_Barrier(ED_MPI_COMM,ED_MPI_ERR)
#endif
  end subroutine ed_init_solver_lattice
#undef INPUT_LIST





  !+------------------------------------------------------------------+
  !PURPOSE: solve the impurity problems for a single or many independent
  ! lattice site using ED. 
  !
  ! The MPI Communicator is passed here.
  !+------------------------------------------------------------------+
#ifdef _MPI
#define INPUT_LIST MpiComm,bath
#else
#define INPUT_LIST bath
#endif
  subroutine ed_solve_single(INPUT_LIST)
#ifdef _MPI
    integer                         :: MpiComm
#endif
    real(8),dimension(:),intent(in) :: bath
    logical                         :: check
#ifdef _MPI
    ED_MPI_COMM   = MpiComm
    ED_MPI_ID     = MPI_Get_Rank(ED_MPI_COMM)
    ED_MPI_SIZE   = MPI_Get_Size(ED_MPI_COMM)
    ED_MPI_MASTER = MPI_Get_Master(ED_MPI_COMM)
#endif
    check = check_bath_dimension(bath)
    if(.not.check)stop "init_ed_solver: wrong bath dimensions"
    call allocate_dmft_bath(dmft_bath)
    call set_dmft_bath(bath,dmft_bath)
    if(ED_MPI_MASTER)then
       if(ed_verbose<2)call write_dmft_bath(dmft_bath,LOGfile)
       call save_dmft_bath(dmft_bath,used=.true.)
    endif
    !SOLVE THE QUANTUM IMPURITY PROBLEM:
    call diagonalize_impurity         !find target states by digonalization of Hamiltonian
    call buildgf_impurity             !build the one-particle impurity Green's functions
    if(chiflag)call buildchi_impurity !build the local susceptibilities (spin [todo charge])
    call observables_impurity         !obtain impurity observables as thermal averages.  
    call local_energy_impurity        !obtain the local energy of the effective impurity problem.
    call deallocate_dmft_bath(dmft_bath)   
    call es_delete_espace(state_list)
#ifdef _MPI
    call MPI_Barrier(ED_MPI_COMM,ED_MPI_ERR)
#endif
  end subroutine ed_solve_single
#undef INPUT_LIST


#ifdef _MPI
#define INPUT_LIST MpiComm,bath,Hloc,iprint,Uloc_ii,Ust_ii,Jh_ii
#else
#define INPUT_LIST bath,Hloc,iprint,Uloc_ii,Ust_ii,Jh_ii
#endif
  subroutine ed_solve_lattice(INPUT_LIST)
#ifdef _MPI
    integer          :: MpiComm
#endif
    real(8)          :: bath(:,:) ![Nlat][Nb]
    complex(8)       :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer          :: iprint
    real(8),optional :: Uloc_ii(size(bath,1),Norb)
    real(8),optional :: Ust_ii(size(bath,1))
    real(8),optional :: Jh_ii(size(bath,1))
    !MPI  auxiliary vars
    complex(8)       :: Smats_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    complex(8)       :: Sreal_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lreal)
    complex(8)       :: SAmats_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    complex(8)       :: SAreal_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lreal)
    complex(8)       :: Gmats_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    complex(8)       :: Greal_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lreal)
    complex(8)       :: Fmats_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    complex(8)       :: Freal_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lreal)
    real(8)          :: nii_tmp(size(bath,1),Norb)
    real(8)          :: dii_tmp(size(bath,1),Norb)
    real(8)          :: mii_tmp(size(bath,1),Norb)
    real(8)          :: pii_tmp(size(bath,1),Norb)
    real(8)          :: eii_tmp(size(bath,1),4)
    real(8)          :: ddii_tmp(size(bath,1),4)
    !
    integer          :: neigen_sectortmp(size(bath,1),Nsectors)
    integer          :: neigen_totaltmp(size(bath,1))
    ! 
    integer          :: ilat,iorb,jorb,ispin,jspin
    integer          :: Nsites
    logical          :: check_dim
    character(len=5) :: tmp_suffix
#ifdef _MPI    
    integer          :: MPI_COLOR
    integer          :: MPI_COLOR_COMM
    integer          :: MPI_COLOR_RANK
    integer          :: MPI_COLOR_SIZE
    integer          :: MPI_COLOR_ERR
    !
    ED_MPI_COMM   = MpiComm
    ED_MPI_ID     = MPI_Get_Rank(ED_MPI_COMM)
    ED_MPI_SIZE   = MPI_Get_Size(ED_MPI_COMM)
    ED_MPI_MASTER = MPI_Get_Master(ED_MPI_COMM)
#endif
    !
    ! Check dimensions !
    Nsites=size(bath,1)
    !
    !Allocate the local static observarbles global to the module
    !One can retrieve these values from suitable routines later on
    if(allocated(nii))deallocate(nii)
    if(allocated(dii))deallocate(dii)
    if(allocated(mii))deallocate(mii)
    if(allocated(pii))deallocate(pii)
    if(allocated(eii))deallocate(eii)
    if(allocated(ddii))deallocate(ddii)
    allocate(nii(Nsites,Norb))
    allocate(dii(Nsites,Norb))
    allocate(mii(Nsites,Norb))
    allocate(pii(Nsites,Norb))
    allocate(eii(Nsites,4))
    allocate(ddii(Nsites,4))
    !
    !Allocate the self-energies global to the module
    !Once can retrieve these functinos from suitable routines later on
    if(allocated(Smatsii))deallocate(Smatsii)
    if(allocated(Srealii))deallocate(Srealii)
    if(allocated(SAmatsii))deallocate(SAmatsii)
    if(allocated(SArealii))deallocate(SArealii)
    allocate(Smatsii(Nsites,Nspin,Nspin,Norb,Norb,Lmats))
    allocate(Srealii(Nsites,Nspin,Nspin,Norb,Norb,Lreal))
    allocate(SAmatsii(Nsites,Nspin,Nspin,Norb,Norb,Lmats))
    allocate(SArealii(Nsites,Nspin,Nspin,Norb,Norb,Lreal))
    !
    !Allocate the imp GF global to the module
    !Once can retrieve these functinos from suitable routines later on
    if(allocated(Gmatsii))deallocate(Gmatsii)
    if(allocated(Grealii))deallocate(Grealii)
    if(allocated(Fmatsii))deallocate(Fmatsii)
    if(allocated(Frealii))deallocate(Frealii)
    allocate(Gmatsii(Nsites,Nspin,Nspin,Norb,Norb,Lmats))
    allocate(Grealii(Nsites,Nspin,Nspin,Norb,Norb,Lreal))
    allocate(Fmatsii(Nsites,Nspin,Nspin,Norb,Norb,Lmats))
    allocate(Frealii(Nsites,Nspin,Nspin,Norb,Norb,Lreal))
    !
    if(size(neigen_sectorii,1)<Nsites)stop "ed_solve_lattice error: size(neigen_sectorii,1)<Nsites"
    if(size(neigen_totalii)<Nsites)stop "ed_solve_lattice error: size(neigen_totalii,1)<Nsites"
    neigen_sectortmp = 0
    neigen_totaltmp  = 0
    !
    !Check the dimensions of the bath are ok:
    if(ED_MPI_MASTER)then
       do ilat=1,Nsites
          check_dim = check_bath_dimension(bath(ilat,:))
          if(.not.check_dim) stop "init_lattice_bath: wrong bath size dimension "
       end do
    endif
    Smatsii  = zero ; Smats_tmp  = zero
    Srealii  = zero ; Sreal_tmp  = zero
    SAmatsii = zero ; SAmats_tmp = zero
    SArealii = zero ; SAreal_tmp = zero
    Gmatsii  = zero ; Gmats_tmp  = zero
    Grealii  = zero ; Greal_tmp  = zero
    Fmatsii  = zero ; Fmats_tmp  = zero
    Frealii  = zero ; Freal_tmp  = zero
    nii      = 0d0  ; nii_tmp    = 0d0
    dii      = 0d0  ; dii_tmp    = 0d0
    mii      = 0d0  ; mii_tmp    = 0d0
    pii      = 0d0  ; pii_tmp    = 0d0
    eii      = 0d0  ; eii_tmp    = 0d0
    ddii     = 0d0  ; ddii_tmp   = 0d0
    !
    if(ED_MPI_MASTER)call start_timer
    if(.not.ED_MPI_MASTER)LOGfile = 800+mpiID
    !
    if(MPI_Colors==0.OR.MPI_Colors>ED_MPI_SIZE)MPI_Colors=ED_MPI_SIZE
    if(ED_MPI_SIZE<2)MPI_Colors=1
    if(ED_MPI_MASTER)then
       write(LOGfile,*)"MPI_SIZE      =",ED_MPI_SIZE
       write(LOGfile,*)"MPI_COLORS    =",MPI_Colors
       write(LOGfile,*)"MPI_COLOR_SIZE=",ED_MPI_SIZE/MPI_Colors
    endif
    !
    MPI_Color = mod(ED_MPI_RANK,MPI_Colors)
    !
    !Split the user provided communicator into MPI_Colors groups.
    !Each group (or color) communicate via the MPI communicator MPI_Color_Comm
    call MPI_Comm_split(ED_MPI_COMM,MPI_Color,0,MPI_Color_Comm,ED_MPI_ERR)
    !
    !Each group (or color) gets its size
    !Each process gets its color-rank in the new group (or color) 
    MPI_Color_Size = MPI_Get_size(MPI_Color_Comm)
    MPI_Color_Rank = MPI_Get_rank(MPI_Color_Comm)
    do i=0,MPI_Colors-1
       if(MPI_Color==i)then
          do j=0,MPI_Color_Size-1
             if(MPI_Color_Rank==j)then
                write(*,*) "Global ", mpi_rank," is now local rank ",mpi_color_rank," of color: ",mpi_color
             endif
             call MPI_Barrier(MPI_Color_Comm,MPI_COLOR_ERR)
          enddo
       endif
       call MPI_Barrier(ED_MPI_COMM,ED_MPI_ERR)
    enddo
    call MPI_Barrier(ED_MPI_COMM,ED_MPI_ERR)
    if(ED_MPI_MASTER)write(LOGfile,*)""
    !
    !Now we need to assign a Chunk of sites to each group
    !
    do ilat=1+MPI_Color,Nsites,MPI_Colors
       if(MPI_Color_Rank==0)write(LOGfile,*)"Solving site:"//reg(txtfy(ilat,Npad=4))//" by group: "//txtfy(mpi_color)
       ed_file_suffix="_site"//reg(txtfy(ilat,Npad=4))
       !
       !If required set the local value of U per each site
       if(present(Uloc_ii))Uloc(1:Norb) = Uloc_ii(ilat,1:Norb)
       if(present(Ust_ii)) Ust          = Ust_ii(ilat) 
       if(present(Jh_ii))  Jh           = Jh_ii(ilat) 
       !
       !Set the local part of the Hamiltonian.
       call set_Hloc(Hloc(ilat,:,:,:,:))
       ! 
       !Solve the impurity problem for the ilat-th site
       neigen_sector(:)   = neigen_sectorii(ilat,:)
       lanc_nstates_total = neigen_totalii(ilat)
       call ed_solve_single(bath(ilat,:))
       neigen_sectortmp(ilat,:)   = neigen_sector(:)
       neigen_totaltmp(ilat)      = lanc_nstates_total
       Smats_tmp(ilat,:,:,:,:,:)  = impSmats(:,:,:,:,:)
       Sreal_tmp(ilat,:,:,:,:,:)  = impSreal(:,:,:,:,:)
       SAmats_tmp(ilat,:,:,:,:,:) = impSAmats(:,:,:,:,:)
       SAreal_tmp(ilat,:,:,:,:,:) = impSAreal(:,:,:,:,:)
       Gmats_tmp(ilat,:,:,:,:,:)  = impGmats(:,:,:,:,:)
       Greal_tmp(ilat,:,:,:,:,:)  = impGreal(:,:,:,:,:)
       Fmats_tmp(ilat,:,:,:,:,:)  = impFmats(:,:,:,:,:)
       Freal_tmp(ilat,:,:,:,:,:)  = impFreal(:,:,:,:,:)
       nii_tmp(ilat,1:Norb)       = ed_dens(1:Norb)
       dii_tmp(ilat,1:Norb)       = ed_docc(1:Norb)
       mii_tmp(ilat,1:Norb)       = ed_dens_up(1:Norb)-ed_dens_dw(1:Norb)
       pii_tmp(ilat,1:Norb)       = ed_phisc(1:Norb)
       eii_tmp(ilat,:)            = [ed_Epot,ed_Eint,ed_Ehartree,ed_Eknot]
       ddii_tmp(ilat,:)           = [ed_Dust,ed_Dund,ed_Dse,ed_Dph]
    enddo
    if(mpiID==0)call stop_timer
#ifdef _MPI_INEQ
    neigen_sectorii=0
    neigen_totalii =0
    call MPI_ALLREDUCE(neigen_sectortmp,neigen_sectorii,Nsites*Nsectors,MPI_INTEGER,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(neigen_totaltmp,neigen_totalii,Nsites,MPI_INTEGER,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(Smats_tmp,Smatsii,Nsites*Nspin*Nspin*Norb*Norb*Lmats,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(Sreal_tmp,Srealii,Nsites*Nspin*Nspin*Norb*Norb*Lreal,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(SAmats_tmp,SAmatsii,Nsites*Nspin*Nspin*Norb*Norb*Lmats,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(SAreal_tmp,SArealii,Nsites*Nspin*Nspin*Norb*Norb*Lreal,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(Gmats_tmp,Gmatsii,Nsites*Nspin*Nspin*Norb*Norb*Lmats,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(Greal_tmp,Grealii,Nsites*Nspin*Nspin*Norb*Norb*Lreal,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(Fmats_tmp,Fmatsii,Nsites*Nspin*Nspin*Norb*Norb*Lmats,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(Freal_tmp,Frealii,Nsites*Nspin*Nspin*Norb*Norb*Lreal,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(nii_tmp,nii,Nsites*Norb,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(dii_tmp,dii,Nsites*Norb,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(mii_tmp,mii,Nsites*Norb,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(pii_tmp,pii,Nsites*Norb,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(eii_tmp,eii,Nsites*4,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(ddii_tmp,ddii,Nsites*4,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,MPIerr)
#else
    neigen_sectorii=neigen_sectortmp
    neigen_totalii =neigen_totaltmp
    Smatsii  =  Smats_tmp
    Srealii  =  Sreal_tmp
    SAmatsii = SAmats_tmp
    SArealii = SAreal_tmp
    Gmatsii  = Gmats_tmp
    Grealii  = Greal_tmp
    Fmatsii  = Fmats_tmp
    Frealii  = Freal_tmp
    nii      = nii_tmp
    dii      = dii_tmp
    mii      = mii_tmp
    pii      = pii_tmp
    eii      = eii_tmp
    ddii     = ddii_tmp
#endif
    if(mpiID==0)then
       if(allocated(wm))deallocate(wm)
       if(allocated(wr))deallocate(wr)
       allocate(wm(Lmats))
       allocate(wr(Lreal))
       wm = pi/beta*(2*arange(1,Lmats)-1)
       wr = linspace(wini,wfin,Lreal)
       select case(iprint)
       case (0)
          write(LOGfile,*)"Sigma not written on file."
       case(1)                  !print only diagonal elements
          write(LOGfile,*)"write spin-orbital diagonal elements:"
          do ispin=1,Nspin
             do iorb=1,Norb
                suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
                call store_data("LSigma"//reg(suffix),Smatsii(:,ispin,ispin,iorb,iorb,:),wm)
                suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
                call store_data("LSigma"//reg(suffix),Srealii(:,ispin,ispin,iorb,iorb,:),wr)
                if(ed_mode=="superc")then
                   suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
                   call store_data("LSelf"//reg(suffix),SAmatsii(:,ispin,ispin,iorb,iorb,:),wm)
                   suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
                   call store_data("LSelf"//reg(suffix),SArealii(:,ispin,ispin,iorb,iorb,:),wr)
                endif
             enddo
          enddo
       case(2)                  !print spin-diagonal, all orbitals 
          write(LOGfile,*)"write spin diagonal and all orbitals elements:"
          do ispin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
                   call store_data("LSigma"//reg(suffix),Smatsii(:,ispin,ispin,iorb,jorb,:),wm)
                   suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
                   call store_data("LSigma"//reg(suffix),Srealii(:,ispin,ispin,iorb,jorb,:),wr)
                   if(ed_mode=="superc")then
                      suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
                      call store_data("LSelf"//reg(suffix),SAmatsii(:,ispin,ispin,iorb,jorb,:),wm)
                      suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
                      call store_data("LSelf"//reg(suffix),SArealii(:,ispin,ispin,iorb,jorb,:),wr)
                   endif
                enddo
             enddo
          enddo
       case default                  !print all off-diagonals
          write(LOGfile,*)"write all elements:"
          do ispin=1,Nspin
             do jspin=1,Nspin
                do iorb=1,Norb
                   do jorb=1,Norb
                      suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//reg(txtfy(jspin))//"_iw.ed"
                      call store_data("LSigma"//reg(suffix),Smatsii(:,ispin,jspin,iorb,jorb,:),wm)
                      suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//reg(txtfy(jspin))//"_realw.ed"
                      call store_data("LSigma"//reg(suffix),Srealii(:,ispin,jspin,iorb,jorb,:),wr)
                      if(ed_mode=="superc")then
                         suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//reg(txtfy(jspin))//"_iw.ed"
                         call store_data("LSelf"//reg(suffix),Smatsii(:,ispin,jspin,iorb,jorb,:),wm)
                         suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//reg(txtfy(jspin))//"_realw.ed"
                         call store_data("LSelf"//reg(suffix),Srealii(:,ispin,jspin,iorb,jorb,:),wr)
                      endif
                   enddo
                enddo
             enddo
          enddo
       end select
    endif
    ed_file_suffix=""
  end subroutine ed_solve_lattice










  !+------------------------------------------------------------------+
  !PURPOSE: 
  !+------------------------------------------------------------------+
  subroutine ed_rebuild_sigma(bath)
    real(8),dimension(:),intent(in) :: bath
    logical                         :: check
    check = check_bath_dimension(bath)
    if(.not.check)stop "init_ed_solver: wrong bath dimensions"
    call allocate_dmft_bath(dmft_bath)
    call set_dmft_bath(bath,dmft_bath)
    if(ED_MPI_ID==0)then
       if(ed_verbose<2)call write_dmft_bath(dmft_bath,LOGfile)
       call save_dmft_bath(dmft_bath,used=.true.)
    endif
    call rebuildgf_impurity             !build the one-particle impurity Green's functions
    select case(ed_mode)
    case default
       call print_sigma_normal
       call print_impg_normal
    case ("superc")
    case ("nonsu2")
    end select
    call deallocate_dmft_bath(dmft_bath)   
  end subroutine ed_rebuild_sigma
  !
  subroutine ed_rebuild_gimp(bath)
    real(8),dimension(:),intent(in) :: bath
    logical                         :: check
    check = check_bath_dimension(bath)
    if(.not.check)stop "init_ed_solver: wrong bath dimensions"
    call allocate_dmft_bath(dmft_bath)
    call set_dmft_bath(bath,dmft_bath)
    if(ED_MPI_ID==0)then
       if(ed_verbose<2)call write_dmft_bath(dmft_bath,LOGfile)
       call save_dmft_bath(dmft_bath,used=.true.)
    endif
    call rebuildgf_impurity             !build the one-particle impurity Green's functions
    select case(ed_mode)
    case default
       call print_impg_normal
    case ("superc")
    case ("nonsu2")
    end select
    call deallocate_dmft_bath(dmft_bath)   
  end subroutine ed_rebuild_gimp
  !
  subroutine ed_rebuild_g0imp(bath)
    real(8),dimension(:),intent(in) :: bath
    logical                         :: check
    check = check_bath_dimension(bath)
    if(.not.check)stop "init_ed_solver: wrong bath dimensions"
    call allocate_dmft_bath(dmft_bath)
    call set_dmft_bath(bath,dmft_bath)
    if(ED_MPI_ID==0)then
       if(ed_verbose<2)call write_dmft_bath(dmft_bath,LOGfile)
       call save_dmft_bath(dmft_bath,used=.true.)
    endif
    call rebuildgf_impurity             !build the one-particle impurity Green's functions
    select case(ed_mode)
    case default
       call print_impg0_normal
    case ("superc")
    case ("nonsu2")
    end select
    call deallocate_dmft_bath(dmft_bath)   
  end subroutine ed_rebuild_g0imp



  subroutine ed_rebuild_sigma_lattice(bath,Hloc,iprint)
    real(8)          :: bath(:,:) ![Nlat][Nb]
    complex(8)       :: Hloc(size(bath,1),Nspin,Nspin,Norb,Norb)
    integer          :: iprint
    !MPI  auxiliary vars
    complex(8)       :: Smats_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    complex(8)       :: Sreal_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lreal)
    complex(8)       :: SAmats_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lmats)
    complex(8)       :: SAreal_tmp(size(bath,1),Nspin,Nspin,Norb,Norb,Lreal)
    ! 
    integer          :: ilat,iorb,jorb,ispin,jspin,i
    integer          :: Nsites
    logical          :: check_dim
    character(len=5) :: tmp_suffix
    !
    ! Check dimensions !
    Nsites=size(bath,1)
    !
    !Allocate the self-energies global to the module
    !Once can retrieve these functinos from suitable routines later on
    if(allocated(Smatsii))deallocate(Smatsii)
    if(allocated(Srealii))deallocate(Srealii)
    if(allocated(SAmatsii))deallocate(SAmatsii)
    if(allocated(SArealii))deallocate(SArealii)
    allocate(Smatsii(Nsites,Nspin,Nspin,Norb,Norb,Lmats))
    allocate(Srealii(Nsites,Nspin,Nspin,Norb,Norb,Lreal))
    allocate(SAmatsii(Nsites,Nspin,Nspin,Norb,Norb,Lmats))
    allocate(SArealii(Nsites,Nspin,Nspin,Norb,Norb,Lreal))
    !
    !Check the dimensions of the bath are ok:
    if(ED_MPI_ID==0)then
       write(LOGfile,*)"Rebuilding Sigma: have you moved .used bath files to .restart ones?! "
       call sleep(3)
    end if
    do ilat=1+mpiID,Nsites,mpiSIZE
       check_dim = check_bath_dimension(bath(ilat,:))
       if(.not.check_dim) stop "init_lattice_bath: wrong bath size dimension 1 or 2 "
    end do
    Smatsii  = zero ; Smats_tmp  = zero
    Srealii  = zero ; Sreal_tmp  = zero
    SAmatsii = zero ; SAmats_tmp = zero
    SArealii = zero ; SAreal_tmp = zero
    !
    if(mpiID==0)call start_timer
    if(mpiID/=0)LOGfile = 800+mpiID
    do ilat=1+mpiID,Nsites,mpiSIZE
       if(mpiID==0)write(LOGfile,*)"Solving site:"//reg(txtfy(ilat,Npad=4))
       ed_file_suffix="_site"//reg(txtfy(ilat,Npad=4))
       !
       !Set the local part of the Hamiltonian.
       call set_Hloc(Hloc(ilat,:,:,:,:))
       ! 
       !Rebuild for the ilat-th site
       call ed_rebuild_sigma(bath(ilat,:))
       Smats_tmp(ilat,:,:,:,:,:)  = impSmats(:,:,:,:,:)
       Sreal_tmp(ilat,:,:,:,:,:)  = impSreal(:,:,:,:,:)
       SAmats_tmp(ilat,:,:,:,:,:) = impSAmats(:,:,:,:,:)
       SAreal_tmp(ilat,:,:,:,:,:) = impSAreal(:,:,:,:,:)
    enddo
    if(mpiID==0)call stop_timer
#ifdef _MPI_INEQ
    call MPI_ALLREDUCE(Smats_tmp,Smatsii,Nsites*Nspin*Nspin*Norb*Norb*Lmats,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(Sreal_tmp,Srealii,Nsites*Nspin*Nspin*Norb*Norb*Lreal,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(SAmats_tmp,SAmatsii,Nsites*Nspin*Nspin*Norb*Norb*Lmats,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
    call MPI_ALLREDUCE(SAreal_tmp,SArealii,Nsites*Nspin*Nspin*Norb*Norb*Lreal,MPI_DOUBLE_COMPLEX,MPI_SUM,MPI_COMM_WORLD,MPIerr)
#else
    Smatsii  =  Smats_tmp
    Srealii  =  Sreal_tmp
    SAmatsii = SAmats_tmp
    SArealii = SAreal_tmp
#endif
    if(mpiID==0)then
       if(allocated(wm))deallocate(wm)
       if(allocated(wr))deallocate(wr)
       allocate(wm(Lmats))
       allocate(wr(Lreal))
       wm = pi/beta*(2*arange(1,Lmats)-1)
       wr = linspace(wini,wfin,Lreal)
       select case(iprint)
       case (0)
          write(LOGfile,*)"Sigma not written on file."
       case(1)                  !print only diagonal elements
          write(LOGfile,*)"write spin-orbital diagonal elements:"
          do ispin=1,Nspin
             do iorb=1,Norb
                suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
                call store_data("LSigma"//reg(suffix),Smatsii(:,ispin,ispin,iorb,iorb,:),wm)
                suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
                call store_data("LSigma"//reg(suffix),Srealii(:,ispin,ispin,iorb,iorb,:),wr)
                if(ed_mode=="superc")then
                   suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
                   call store_data("LSelf"//reg(suffix),SAmatsii(:,ispin,ispin,iorb,iorb,:),wm)
                   suffix="_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
                   call store_data("LSelf"//reg(suffix),SArealii(:,ispin,ispin,iorb,iorb,:),wr)
                endif
             enddo
          enddo
       case(2)                  !print spin-diagonal, all orbitals 
          write(LOGfile,*)"write spin diagonal and all orbitals elements:"
          do ispin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
                   call store_data("LSigma"//reg(suffix),Smatsii(:,ispin,ispin,iorb,jorb,:),wm)
                   suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
                   call store_data("LSigma"//reg(suffix),Srealii(:,ispin,ispin,iorb,jorb,:),wr)
                   if(ed_mode=="superc")then
                      suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
                      call store_data("LSelf"//reg(suffix),SAmatsii(:,ispin,ispin,iorb,jorb,:),wm)
                      suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
                      call store_data("LSelf"//reg(suffix),SArealii(:,ispin,ispin,iorb,jorb,:),wr)
                   endif
                enddo
             enddo
          enddo
       case default                  !print all off-diagonals
          write(LOGfile,*)"write all elements:"
          do ispin=1,Nspin
             do jspin=1,Nspin
                do iorb=1,Norb
                   do jorb=1,Norb
                      suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//reg(txtfy(jspin))//"_iw.ed"
                      call store_data("LSigma"//reg(suffix),Smatsii(:,ispin,jspin,iorb,jorb,:),wm)
                      suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//reg(txtfy(jspin))//"_realw.ed"
                      call store_data("LSigma"//reg(suffix),Srealii(:,ispin,jspin,iorb,jorb,:),wr)
                      if(ed_mode=="superc")then
                         suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//reg(txtfy(jspin))//"_iw.ed"
                         call store_data("LSelf"//reg(suffix),Smatsii(:,ispin,jspin,iorb,jorb,:),wm)
                         suffix="_l"//reg(txtfy(iorb))//reg(txtfy(jorb))//"_s"//reg(txtfy(ispin))//reg(txtfy(jspin))//"_realw.ed"
                         call store_data("LSelf"//reg(suffix),Srealii(:,ispin,jspin,iorb,jorb,:),wr)
                      endif
                   enddo
                enddo
             enddo
          enddo
       end select
    endif
    ed_file_suffix=""
  end subroutine ed_rebuild_sigma_lattice



end module ED_MAIN

