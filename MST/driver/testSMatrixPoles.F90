program testSMatrixPoles
   use KindParamModule, only : IntKind, RealKind, CmplxKind
!
   use ErrorHandlerModule, only : ErrorHandler, WarningHandler
!
   use DataServiceCenterModule, only : isDataStorageExisting, &
                                       getDataStorage, RealMark
!
   use TimerModule, only : getTime
!
   use SystemModule, only : getNumAtoms, getAtomPosition, getAtomicNumber
!
   use ScfDataModule, only : n_spin_pola, n_spin_cant
   use ScfDataModule, only : ErBottom, ErTop, EiBottom, EiTop, Temperature
   use ScfDataModule, only : istop, EvBottom, isNonRelativisticCore
   use ScfDataModule, only : ngaussr, ngaussq
   use ScfDataModule, only : pole_step
!
   use InputModule, only : getKeyValue
!
   use AtomModule, only : getLocalAtomicNumber, getLocalNumSpecies
!
   use MathParamModule, only : ZERO, TEN2m8, TEN2m6, THIRD, HALF, ONE, TWO, PI, FIVE, PI2, PI4, &  
                               CZERO, CONE, SQRTm1, Y0
!
   use SphericalHarmonicsModule, only : initSphericalHarmonics
   use SphericalHarmonicsModule, only : endSphericalHarmonics
!
   use GauntFactorsModule, only : initGauntFactors, endGauntFactors
!
   use MadelungModule, only : initMadelung, endMadelung
!
   use SpinRotationModule, only : initSpinRotation, calSpinRotation, endSpinRotation
!
   use SystemSymmetryModule, only : initSystemSymmetry, endSystemSymmetry,   &
                                    calSymmetryFlags
!
   use CoreStatesModule, only : initCoreStates, calCoreStates, endCoreStates
   use CoreStatesModule, only : readCoreStates, printCoreStates, printCoreDensity
   use CoreStatesModule, only : getSemiCoreStates
!
   use PolyhedraModule, only : initPolyhedra, endPolyhedra
   use PolyhedraModule, only : getVolume, getInscrSphVolume
!
   use StepFunctionModule, only : initStepFunction, endStepFunction
   use StepFunctionModule, only : getVolumeIntegration
!
   use OutputModule, only : getStandardOutputLevel
!
   use Atom2ProcModule, only : getLocalNumAtoms, getGlobalIndex
!
   use PotentialModule, only : initPotential, endPotential
   use PotentialModule, only : readPotential
!
   use SurfElementsModule, only : initSurfElements, endSurfElements,  &
                                  genGaussPoints, genGaussSphHarmonics
!
   use SSSolverModule, only : initSSSolver, endSSSolver
   use SSSolverModule, only : solveSingleScattering
   use SSSolverModule, only : computeDOS, getDOS
!
   use PublicTypeDefinitionsModule, only : GridStruct
!
   use RadialGridModule, only : getMaxNumRmesh, getGrid
!
   use WriteFunctionModule, only : writeFunction
!
   use IntegerFactorsModule, only : initIntegerFactors, endIntegerFactors, &
                                    mofj, lofj
   use MPPModule, only : syncAllPEs
!
   use LatticeModule, only : initLattice, endLattice, getLatticeType
!
   use IBZRotationModule, only : initIBZRotation, endIBZRotation, computeRotationMatrix
!
   use SMatrixPolesModule, only : initSMatrixPoles, endSMatrixPoles, &
                                  findSMatrixPoles, computeBoundStateDensity, &
                                  computeResonanceStateDensity,               &
                                  printSMatrixPoleInfo, printBoundStateDensity
!
   implicit   none
!
   logical :: non_zero
!
   character (len=6) :: state_string, jl_string
   character (len=8) :: app_string
   character (len=50) :: file_name
!
   integer (kind=IntKind) :: iprint = 0
   integer (kind=IntKind) :: NumAtoms, LocalNumAtoms
   integer (kind=IntKind) :: lmax_max, lmax_pot_max, lmax_kkr_max, jmax_rho, &
                             lmax_phi_max, lmax_rho_max, lmax_step_max, lmax_green_max
   integer (kind=IntKind) :: kmax_kkr, kmax_kkr_max, jmax_rho_max
   integer (kind=IntKind) :: id, ig, is, ia, i, ib, jl, l, m, numc
   integer (kind=IntKind) :: RelativisticFlag
   integer (kind=IntKind) :: node_print_level, rstatus
!
   integer (kind=IntKind), allocatable :: atom_print_level(:)
   integer (kind=IntKind), allocatable :: GlobalIndex(:)
   integer (kind=IntKind), allocatable :: AtomicNumber(:)
   integer (kind=IntKind), allocatable :: lmax_pot(:)
   integer (kind=IntKind), allocatable :: lmax_kkr(:)
   integer (kind=IntKind), allocatable :: lmax_phi(:)
   integer (kind=IntKind), allocatable :: lmax_rho(:)
   integer (kind=IntKind), allocatable :: lmax_green(:)
   integer (kind=IntKind), allocatable :: lmax_step(:)
   integer (kind=IntKind), allocatable :: LocalNumSpecies(:)
   integer (kind=IntKind) :: eGID, NumPEsInEGroup, MyPEInEGroup
   integer (kind=IntKind) :: kl, klp, kl1, kl2, kl3, ir, nr, occ, ie
!
   real (kind=RealKind), pointer :: bravais(:,:)
   real (kind=RealKind), pointer :: r_mesh(:)
   real (kind=RealKind), allocatable :: AtomPosition(:,:)
   real (kind=RealKind) :: t0, t1, t2, ebot, etop, rfac, Efermi, resonance_width
   real (kind=RealKind), pointer :: ec(:)
!
   real (kind=RealKind), parameter :: ZeroIntHalfWidth = TEN2m6
!
   complex (kind=CmplxKind) :: e 
   complex (kind=CmplxKind), pointer :: dos_r_jl(:,:)
!
   type (GridStruct), pointer :: Grid
!
!  -------------------------------------------------------------------
   call startProcess()
!  -------------------------------------------------------------------
   t0 = getTime()
!  -------------------------------------------------------------------
   call initializeModules()
!  -------------------------------------------------------------------
   call initCoreStates(LocalNumAtoms,EvBottom,n_spin_pola,            &
                       isNonRelativisticCore(),istop,1)
!  -------------------------------------------------------------------
   call initSSSolver(LocalNumAtoms, getLocalNumSpecies, getLocalAtomicNumber, &
                     lmax_kkr, lmax_phi, lmax_pot, lmax_step, lmax_green,  &
                     n_spin_pola, n_spin_cant, RelativisticFlag, istop, atom_print_level)
!  -------------------------------------------------------------------
   call syncAllPEs()
!  -------------------------------------------------------------------
!
!  ===================================================================
!  Check the symmetry of single site density at an energy > 0
!  ===================================================================
   do id = 1, LocalNumAtoms
      Grid => getGrid(id)
      do is = 1,n_spin_pola
!        -------------------------------------------------------------
         call solveSingleScattering(is, id, (0.6d0,0.0d0), CZERO)
         call computeDOS()
         dos_r_jl => getDOS()
!        -------------------------------------------------------------
         jl = 0
         do l = 0, lmax_green(id)
            do m = 0, l
               jl = jl + 1
               non_zero = .false.
               LOOP_ir_2: do ir = 1, Grid%jend
                  if (abs(dos_r_jl(ir,jl)) > TEN2m6) then
                     non_zero = .true.
                     exit LOOP_ir_2
                  endif
               enddo LOOP_ir_2
               if (non_zero .and. node_print_level >= 0) then
                  write(6,'(a,i2,a,i2,a)')'Non-zero single site density component at (l,m) channel: (',l,',',m,')'
               endif
            enddo
         enddo
      enddo
   enddo
!
   write(6,'(/,a,f12.5,a)') 'Setup time: ',getTime() - t0,' sec.'
!
!  ===================================================================
!  read core states and density data of local atoms from file
!  ===================================================================
   call readCoreStates()
!  -------------------------------------------------------------------
   call calCoreStates()
!  -------------------------------------------------------------------
   do id = 1,LocalNumAtoms
      if (atom_print_level(id) >= 0) then
!        -------------------------------------------------------------
         call printCoreStates(id)
         call printCoreDensity(id)
!        -------------------------------------------------------------
      endif
   enddo
!
!  -------------------------------------------------------------------
   call initIntegerFactors(lmax_kkr_max)
!  -------------------------------------------------------------------
!
   allocate(LocalNumSpecies(LocalNumAtoms))
   do id = 1,LocalNumAtoms
      LocalNumSpecies(id) = getLocalNumSpecies(id)
   enddo
!
!  -------------------------------------------------------------------
   call initSMatrixPoles(LocalNumAtoms,n_spin_pola,LocalNumSpecies,   &
                         lmax_kkr,lmax_rho,iprint=0)
!  -------------------------------------------------------------------
!
   rstatus = getKeyValue(1,'Resonance State Max Width (>0.0)',resonance_width)
!
   t1 = getTime()
   do id = 1,LocalNumAtoms
      do ia = 1, getLocalNumSpecies(id)
         do is = 1,n_spin_pola
            ec => getSemiCoreStates(id,ia,is,numc)
            ebot = ec(1) - HALF
!           etop = ec(numc) + HALF
!           if (etop > ZERO) then
!              etop = -TEN2m6
!           endif
            etop = Efermi; ebot = ErBottom
!           ---------------------------------------------------------
            call findSMatrixPoles(id,ia,is,ebot,etop,Delta=pole_step, &
                                  MaxResWidth = resonance_width,      &
                                  CheckPoles =.false.)
!           ---------------------------------------------------------
            call computeBoundStateDensity(id,ia,is)
!           ---------------------------------------------------------
            call computeResonanceStateDensity(id,ia,is)
!           ---------------------------------------------------------
            if (node_print_level >= 0) then
!              ------------------------------------------------------
               call printSMatrixPoleInfo(id,ia,is)
!              ------------------------------------------------------
               call printBoundStateDensity(id,ia,is)
!              ------------------------------------------------------
            endif
         enddo
      enddo
   enddo
   if (node_print_level >= 0) then
      write(6,'(/,a,f12.5,a,/)') 'Quadratic technique time: ',getTime() - t1,' sec.'
   endif
!
!  -------------------------------------------------------------------
   call endIntegerFactors()
!  -------------------------------------------------------------------
!
   if (node_print_level >= 0) then
      write(6,*) " Run Ending! "
      call FlushFile(6)
   endif
!
   deallocate(LocalNumSpecies)
!
!  ===================================================================
!  finish the process
!  -------------------------------------------------------------------
   call endSSSolver()
   call endCoreStates()
   call cleanModules()
   call finishProcess()
!  -------------------------------------------------------------------
!
contains
!
!  ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
   subroutine initializeModules()
!  ===================================================================
   use PublicTypeDefinitionsModule, only : GridStruct
   use ScfDataModule, only : isNonRelativisticValence
   use ScfDataModule, only : isScalarRelativisticValence
   use ScfDataModule, only : getSingleSiteSolverMethod
   use ScfDataModule, only : isRelativisticValence, Symmetrize
   use AtomModule, only : getPotLmax, getKKRLmax, getPhiLmax, getRhoLmax, getStepFuncLmax
   use AtomModule, only : setTruncPotLmax, getTruncPotLmax, setPotLmax, getLocalEvec
   use PotentialTypeModule, only : isTestPotential, isFullPotential
   use TestPotentialModule, only : initTestPotential, endTestPotential,      &
                                   readTestPotential, getTestPotential,      &
                                   getTestPotEf, getTestV0
   use RadialGridModule, only : getGrid
   use PotentialModule, only : getPotEf, setV0, setPotential, isPotComponentZero, getSphPotr
   use PotentialModule, only : getPotComponentFlag, getTruncatedPotComponentFlag
   use PotentialModule, only : getPotential, getTruncatedPotential
   use ContourModule, only : getEPoint, setupContour
   use ProcMappingModule, only : getNumEsOnMyProc, getEnergyIndex
!
   implicit none
!
   integer (kind=IntKind) :: i, id, ig, is, l, m, jl, ie_glb, ie_loc
   integer (kind=IntKind) :: jmax_pot, jmax_rho, NumEsOnMyProc
   integer (kind=IntKind) :: ndivin, ndivout, nmult, lmax_max
!
   real (kind=RealKind) :: rmt, rend, rws, rinsc, v0
   real (kind=RealKind), pointer :: potr_0(:)
   real (kind=RealKind), allocatable :: evec(:,:)
!
   real (kind=RealKind), parameter :: xstart = -.1113096740000D+02
!
   complex (kind=CmplxKind), pointer :: EPoint(:)
   complex (kind=CmplxKind), pointer :: pot_l(:), pot_jl(:,:)
   complex (kind=CmplxKind) :: energy
!
   type (GridStruct), pointer :: Grid
!
   logical :: non_zero
!
   integer (kind=IntKind), pointer :: pflag(:)
!
   NumAtoms = getNumAtoms()
   LocalNumAtoms=getLocalNumAtoms()
!
   allocate(AtomPosition(1:3,1:NumAtoms))
   allocate(AtomicNumber(NumAtoms))
   allocate(GlobalIndex(LocalNumAtoms))
   do i=1,NumAtoms
      AtomPosition(1:3,i)=getAtomPosition(i)
      AtomicNumber(i) = getAtomicNumber(i)
   enddo
!
   node_print_level = getStandardOutputLevel()
!
   allocate(atom_print_level(1:LocalNumAtoms))
   do i=1,LocalNumAtoms
      atom_print_level(i) = getStandardOutputLevel(i)
   enddo
!
!  ===================================================================
!  If it is not the full-potential calculation, set the Lmax for potential to 0             
!  ===================================================================
   if (.not.isFullPotential()) then
      do i=1,LocalNumAtoms
!        -------------------------------------------------------------
         call setPotLmax(i,0)
         call setTruncPotLmax(i,0)
!        -------------------------------------------------------------
      enddo
   endif
!
!  ===================================================================
!  setup the Lmax values.             
!  ===================================================================
   allocate(lmax_pot(LocalNumAtoms), lmax_rho(LocalNumAtoms))
   allocate(lmax_kkr(LocalNumAtoms), lmax_phi(LocalNumAtoms))
   allocate(lmax_step(LocalNumAtoms))
   allocate(lmax_green(LocalNumAtoms))
   lmax_kkr_max = 0
   lmax_phi_max = 0
   lmax_rho_max = 0
   lmax_pot_max = 0
   lmax_step_max = 0
   lmax_green_max = 0
   lmax_max = 0
   do i=1,LocalNumAtoms
      lmax_kkr(i) = getKKRLmax(i)
      lmax_phi(i) = getPhiLmax(i)
      lmax_rho(i) = getRhoLmax(i)
      lmax_pot(i) = getPotLmax(i)
      lmax_kkr_max = max(lmax_kkr_max,lmax_kkr(i))
      lmax_phi_max = max(lmax_phi_max,lmax_phi(i))
      lmax_rho_max = max(lmax_rho_max,lmax_rho(i))
      lmax_pot_max = max(lmax_pot_max,lmax_pot(i))
      if (isFullPotential()) then
         lmax_step(i)  = max(getStepFuncLmax(i),lmax_phi(i)*2)
!        lmax_max = max( lmax_max, 2*lmax_step(i), 2*lmax_pot(i),     &
!                        2*lmax_rho(i), lmax_phi(i) )
         lmax_max = max(lmax_max,2*getPhiLmax(i),2*lmax_rho(i),lmax_step(i))
      else
         lmax_step(i)  = getStepFuncLmax(i)
         lmax_max = max( lmax_max, lmax_step(i), lmax_rho(i), lmax_kkr(i), lmax_phi(i) )
      endif
      lmax_step_max = max(lmax_step_max,lmax_step(i))
!     lmax_green(i) = min(2*lmax_phi(i),lmax_rho(i))
      lmax_green(i) = lmax_rho(i)
      lmax_green_max = max(lmax_green(i),lmax_green_max)
   enddo
!
   jmax_rho_max = (lmax_rho_max+1)*(lmax_rho_max+2)/2
   kmax_kkr_max = (lmax_kkr_max+1)**2
!
!  -------------------------------------------------------------------
!  call initSphericalHarmonics(4*lmax_max)
   call initSphericalHarmonics(2*lmax_max)
!  -------------------------------------------------------------------
!
!  ===================================================================
!  initilize GauntFactors:
!  ===================================================================
!  call initGauntFactors(2*lmax_max,istop,0)
   call initGauntFactors(lmax_max,istop,0)
!  -------------------------------------------------------------------
!
   do i=1,LocalNumAtoms
      ig=getGlobalIndex(i)
      GlobalIndex(i)=ig
   enddo
!
!  -------------------------------------------------------------------
   call setupRadGridAndCell(LocalNumAtoms,lmax_max)
!  -------------------------------------------------------------------
!
   if (isDataStorageExisting('Bravais Vector')) then
!     ----------------------------------------------------------------
      bravais => getDataStorage('Bravais Vector',3,3,RealMark)
!     ----------------------------------------------------------------
   else
!     ----------------------------------------------------------------
      call ErrorHandler('testSineMatrixPole','Bravais vector data does not exist')
!     ----------------------------------------------------------------
   endif
!
!  ===================================================================
!  initialize potential module
!  -------------------------------------------------------------------
   call initMadelung(LocalNumAtoms,NumAtoms,GlobalIndex,              &
                     lmax_rho_max,lmax_pot_max,bravais,AtomPosition,0)
!  -------------------------------------------------------------------
!
!  -------------------------------------------------------------------
   call initSystemSymmetry( NumAtoms, LocalNumAtoms, lmax_pot, lmax_step, atom_print_level )
!  -------------------------------------------------------------------
   call calSymmetryFlags()
!  -------------------------------------------------------------------
!
!  ===================================================================
!  -------------------------------------------------------------------
   call initPotential(LocalNumAtoms,lmax_pot,lmax_step,               &
                      n_spin_pola,n_spin_cant,istop,atom_print_level)
!  -------------------------------------------------------------------
!
   if (isTestPotential()) then
!     ----------------------------------------------------------------
      call initTestPotential(LocalNumAtoms,n_spin_pola)
!     ----------------------------------------------------------------
      call readTestPotential(lmax_pot)
!     ----------------------------------------------------------------
      do id = 1, LocalNumAtoms
         jmax_pot = (lmax_pot(id)+1)*(lmax_pot(id)+2)/2
         do is = 1,n_spin_pola
            do jl=1,jmax_pot
!              -------------------------------------------------------
               pot_l => getTestPotential(id,is,jl)
!              -------------------------------------------------------
               call setPotential(id,1,is,jl,pot_l,1)
!              -------------------------------------------------------
            enddo
         enddo
      enddo
      do is = 1,n_spin_pola
         v0 = getTestV0(is)
         call setV0(is,v0)
      enddo
      Efermi=getTestPotEf()
!     ----------------------------------------------------------------
      call endTestPotential()
!     ----------------------------------------------------------------
   else
!     ================================================================
!     read potential data
!     ----------------------------------------------------------------
      call readPotential()
!     ----------------------------------------------------------------
      do id = 1, LocalNumAtoms
         Grid => getGrid(id)
         ig = GlobalIndex(id)
         do is = 1,n_spin_pola
            jl = 0
            do l = 0, lmax_pot(id)
               do m = 0, l
                  jl = jl + 1
                  if (.not.isPotComponentZero(id,jl) .and. node_print_level >= 0) then
                     write(6,'(a,i2,a,i2,a)')'Non-zero potential component at (l,m) channel: (',l,',',m,')'
                  endif
               enddo
            enddo
            potr_0 =>  getSphPotr(id,1,is)
         enddo
         write(6,'(/)')
         pflag => getPotComponentFlag(id)
         jl = 0
         do l = 0, lmax_pot(id)
            do m = 0, l
               jl = jl + 1
               if (pflag(jl) /= 0 .and. node_print_level >= 0) then
                  write(6,'(a,i2,a,i2,a)')'pflag<>0 component at (l,m) channel: (',l,',',m,')'
               endif
            enddo
         enddo
         if (isFullPotential()) then
            write(6,'(/)')
            pflag => getTruncatedPotComponentFlag(id)
            jl = 0
            do l = 0, lmax_pot(id)
               do m = 0, l
                  jl = jl + 1
                  if (pflag(jl) /= 0 .and. node_print_level >= 0) then
                     write(6,'(a,i2,a,i2,a)')'Truncated pflag<>0 component at (l,m) channel: (',l,',',m,')'
                  endif
               enddo
            enddo
         endif
         do is = 1,n_spin_pola
            write(6,'(/,a,i2)')'spin = ',is
            pot_jl => getPotential(id,1,is)
            jl = 0
            do l = 0, lmax_pot(id)
               do m = 0, l
                  jl = jl + 1
                  non_zero = .false.
                  LOOP_ir: do ir = 1, Grid%jend
                     if (abs(pot_jl(ir,jl)) > TEN2m6) then
                        non_zero = .true.
                        exit LOOP_ir
                     endif
                  enddo LOOP_ir
                  if (non_zero .and. node_print_level >= 0) then
                     write(6,'(a,i2,a,i2,a)')'Recheck non-zero potential component at (l,m) channel: (',l,',',m,')'
                  endif
               enddo
            enddo
            if (isFullPotential()) then
               write(6,'(/)')
               pot_jl => getTruncatedPotential(id,1,is)
               jl = 0
               do l = 0, getTruncPotLmax(id)
                  do m = 0, l
                     jl = jl + 1
                     non_zero = .false.
                     LOOP_ir_1: do ir = 1, Grid%jend-Grid%jmt+1
                        if (abs(pot_jl(ir,jl)) > TEN2m6) then
                           non_zero = .true.
                           exit LOOP_ir_1
                        endif
                     enddo LOOP_ir_1
                     if (non_zero .and. node_print_level >= 0) then
                        write(6,'(a,i2,a,i2,a)')'Recheck non-zero truncated potential component at (l,m) channel: (',l,',',m,')'
                     endif
                  enddo
               enddo
            endif
         enddo
      enddo
   endif
!
   if (ErTop > ZERO) then
      Efermi = ErTop
   else
      Efermi=getPotEf()
   endif
!
   call initSpinRotation(LocalNumAtoms)
   allocate(evec(3,LocalNumAtoms))
   do i = 1,LocalNumAtoms
      evec(1:3,i) = getLocalEvec(i,'old')
!     ----------------------------------------------------------------
      call calSpinRotation(i,evec(1:3,i))
!     ----------------------------------------------------------------
   enddo
!  -------------------------------------------------------------------
   call setupContour( ErBottom, Efermi, EiBottom, EiTop )
!  -------------------------------------------------------------------
!
   EPoint => getEPoint()
   NumEsOnMyProc = getNumEsOnMyProc()
   write(6,'(/,a)')'=================================================='
   write(6,'(  a)')'Energy #                    Energy Value'
   write(6,'(  a)')'--------------------------------------------------'
   do ie_loc = 1, NumEsOnMyProc
      ie_glb = getEnergyIndex(ie_loc)
      energy = EPoint(ie_glb)
      write(6,'(i5,12x,2d16.8)')ie_glb,energy
   enddo
   write(6,'(  a)')'=================================================='
!
   if (getSingleSiteSolverMethod() == -1) then
      call initSurfElements('none',-1)
      call genGaussPoints()
      call genGaussSphHarmonics(lmax_max)
   endif
!  -------------------------------------------------------------------
!
!  ===================================================================
!  Initialize the the lattice system and crystal symmetry
!  -------------------------------------------------------------------
   call initLattice(bravais)
!  -------------------------------------------------------------------
   call initIBZRotation(isRelativisticValence(),getLatticeType(),     &
                        lmax_kkr_max,Symmetrize)
   call computeRotationMatrix(bravais,NumAtoms,AtomPosition,anum=AtomicNumber)
!  -------------------------------------------------------------------
!
!  ===================================================================
!  initialize single scattering solver
!  ===================================================================
   if (isNonRelativisticValence()) then
      RelativisticFlag = 0
   else if (isScalarRelativisticValence()) then
      RelativisticFlag = 1
   else
      RelativisticFlag = 2
   endif
   
   end subroutine initializeModules
!  ===================================================================
!
!  ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
   subroutine cleanModules()
!  ===================================================================
   use RadialGridModule, only : endRadialGrid
   implicit none
!
   deallocate( atom_print_level )
   deallocate( AtomPosition,AtomicNumber,lmax_kkr,lmax_phi,lmax_rho,lmax_pot )
   deallocate( lmax_step, lmax_green, GlobalIndex )
!
   call endIBZRotation()
   call endLattice()
   call endSurfElements()
   call endSpinRotation()
   call endPotential()
   call endStepFunction()
   call endRadialGrid()
   call endSystemSymmetry()
   call endMadelung()
   call endGauntFactors()
   call endSphericalHarmonics()
!
   end subroutine cleanModules
!  ===================================================================
end program testSMatrixPoles
