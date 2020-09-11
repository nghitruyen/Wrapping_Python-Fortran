!======================================================================================================================!
!
!                    DassFlow Version 2.0
!
!======================================================================================================================!
!
!  Copyright University of Toulouse-INSA - CNRS (France)
!
!  This file is part of the DassFlow software (Data Assimilation for Free Surface Flows).
!  DassFlow is a computational software aiming at simulating geophysical free surface flows.
!  It is designed for Variational Data Assimilation (4D-var) and sensitivity analyses. 
! Inverse capabilities are based on the adjoint code which is generated by 
! a source-to-source algorithmic differentiation (Tapenade software used).
!
!  DassFlow software includes few mostly independent "modules" with common architectures and structures:
!    - DassFlow 2DShallow (shallow water equations in (h,q), finite volumes), i.e. the present code.
!    - DassFlow3D  (non-linear Stokes equations, finite elements, mobile geometries, ALE).
!    - DassFlow 1D (shallow water equations in (S,Q), finite volumes or finite differences), river hydraulics.
!  Please consult the DassFlow webpage for more details: http://www.math.univ-toulouse.fr/DassFlow
!
! You have used DassFlow in an article, a scientific document etc ?  How to cite us ? Please consult the webpage.
! 
!  Many people have contributed to the DassFlow developments from the initial version to the latest ones.
!  Current main developers or scientific contributers are:
!               P. Brisset (CNES & Mathematics Institute of Toulouse & INSA Toulouse)
!               F. Couderc (CNRS & Mathematics Institute of Toulouse IMT)
!               P.-A. Garambois (INSA & ICUBE Strasbourg)
!               J. Monnier (INSA & Mathematics Institute of Toulouse IMT).
!               J.-P. Vila (INSA & Mathematics Institute of Toulouse IMT).
!  and former other developers (R. Madec, M. Honnorat and J. Marin).
!
!  Scientific contact : jerome.monnier@insa-toulouse.fr
!  Technical  contacts : frederic.couderc@math.univ-toulouse.fr, pierre.brisset@insa-toulouse.fr
!
!  This software is governed by the CeCILL license under French law and abiding by the rules of distribution
!  of free software. You can use, modify and/or redistribute the software under the terms of the CeCILL license
!  as circulated by CEA, CNRS and INRIA at the following URL: "http://www.cecill.info".
!
!  As a counterpart to the access to the source code and rights to copy, modify and redistribute granted by the
!  license, users are provided only with a limited warranty and the software's author, the holder of the economic
!  rights, and the successive licensors have only limited liability.
!
!  In this respect, the user's attention is drawn to the risks associated with loading, using, modifying and/or
!  developing or reproducing the software by the user in light of its specific status of free software, that may
!  mean that it is complicated to manipulate, and that also therefore means that it is reserved for developers and
!  experienced professionals having in-depth computer knowledge. Users are therefore encouraged to load and test the
!  software's suitability as regards their requirements in conditions enabling the security of their systems and/or
!  data to be ensured and, more generally, to use and operate it in the same conditions as regards security.
!
!  The fact that you are presently reading this means that you have had knowledge of the CeCILL license and that you
!  accept its terms.
!
!======================================================================================================================!
!> \file euler_time_step_first.f90
!! \brief This file includes the computation with HLL method without MUSCL and slope limiter. An unique subroutine :
!! euler_time_step_first

!> Subroutine of the computation with HLL method without MUSCL and slope limiter.  
!!
!! \details Algorithm used:
!!
!!     Update boundaries conditions
!!     Update mvector
!!     Update pressure
!!
!!     do i = 2, n:
!!       Computation of F (HLL)
!!     end do
!!     
!!     do i = 2, n:
!!       s(i) = max(0,s-(dt/dxi) (F1(i+1)-F1(i)))
!!       q(i) = max(0,q-(dt/dxi) (F2(i+1)-F2(i)))
!!       Update mvector(i)
!!       Update H(i) (from S(i))
!!       Computation of Sg(i) and Sf(i)
!!       q(i) = q + dt(sg+sf)
!!     end do
!!
!! \param[in]  dof Unknowns of the model.
!! \param[in]    mesh Mesh of the model.
SUBROUTINE euler_time_step_first( dof , mesh )

   USE m_common
   USE m_mesh
   USE m_time_screen                                                                                              !NOADJ    
   USE m_model
   USE m_numeric
   implicit none

!======================================================================================================================!
!  Interface Variables
!======================================================================================================================!

   type( msh ), intent(in   )  ::  mesh   ! Mesh of model

   type( unk ), intent(inout)  ::  dof    ! Unknow of model

!======================================================================================================================!
!  Local Variables
!======================================================================================================================!

   real(rp)  ::  qL , sL,hl                                ! Flow,surface and height to cell left

   real(rp)  ::  qR , sR,hr                                ! Flow,surface and height to cell right

   real(rp)  ::  ur,uL, hbis

   real(rp)  ::  flux(2)                                   ! Temporary flux ( output of hhl function)

   real(rp), dimension(mesh%ncs+4 )  ::  tfluxbbr          ! Flux1 for finite volume schem
   
   real(rp), dimension(mesh%ncs+4 ) ::  tfluxbbl           ! Flux1 for finite volume schem

   real(rp), dimension(mesh%ncs+4) :: pressureSg           ! Pressure for fluxes computing

   integer(ip), dimension(mesh%ncs+4) :: mVector           ! Pressure for fluxes computing

   real(rp)  ::  q,S,fr                                    ! Temporary primitive variables

   real(rp)  :: A                                          ! Temporary variable

   real(rp)  :: dz                                         ! Local slope

   real(rp)  :: Manning                                    ! Value of Manning

   real(rp)  :: SourceTerm                                 ! Source Term

   real(rp)  :: SourceTermPente                            ! Source Term slope

   real(rp)  :: SourceTermB                                ! Source B Term
   
   real(rp)  :: SourceTermFriction                         ! Sources terme Friction

   real(rp)  :: sgie                                       ! Pressure source term at the cell ie

   real(rp)  :: hydraulicRadiusie                          ! Hydraulic Radius at the cell ie

   real(rp)  :: PerimeterFromH                             ! Perimeriter at the cell ie

   real(rp)  :: pl,pr

   real(rp)  :: temp
   
   !QLAT
   real(rp)  :: qlat, qlat_mass, qlat_qdm   ! Lateral inflow in m3.s-1, m2.s-1, m3.s-2
   real(rp)  :: dx, B, ulat ! dx et width in meters (for rectangular channel only !), speed of injection in m/s
   integer   :: loc, iloc ! localization of lateral inflow on mesh and corresponfing flag

   character(len=80) ::  filename

!======================================================================================================================!
!  Begin Subroutine
!======================================================================================================================!

!   print *, "s2(0)=", dof%s(2)
   call calc_boundary_state( mesh,dof)    ! Update of boundary condition 

!   print *, "s2(1)=", dof%s(2)


   call UpdateMVector(mesh,dof,mvector)                 ! Update mvector   
   call pressureSgUpdate(mesh,dof,mvector,pressureSg)   ! Update pressure

   call SurfaceToHeightCrossSection(mesh,dof,1,mvector)          ! Update of dof%h(1)
   call SurfaceToHeightCrossSection(mesh,dof,2,mvector)          ! Update of dof%h(2)
   call SurfaceToHeightCrossSection(mesh,dof,mesh%ncs+3,mvector) ! Update of dof%h(mesh%ncs+3)
   call SurfaceToHeightCrossSection(mesh,dof,mesh%ncs+4,mvector) ! Update of dof%h(mesh%ncs+4)

    select case(lat_inflow)
       case ('1')
         call compute_qlat(dof)
         iloc = 0 !Counter for qlat localisations : advances to read next ie value in bc%hyd_lat%loc
    end select
   !===================================
   !  Flux computation  
   !===================================
   do ie= 3,mesh%ncs+3

      
      hl=dof%h(ie-1)
      sl=dof%s(ie-1)
      ql=dof%q(ie-1)
      pl=pressureSg(ie-1)

      hr=dof%h(ie  )
      sr=dof%s(ie  )
      qr=dof%q(ie  )
      pr=pressureSg(ie  )
      
! ! ! !       
! ! ! !       if (hl < 1e-16) then
! ! ! !         print *, "[ERR] hl <~ 0", ie-1, hl, tc, tc0
! ! ! !         print *, "             ", bathy_cell(ie-1)
! ! ! !         read(*,*)
! ! ! !       end if
! ! ! !       if (hr < 1e-16) then
! ! ! !         print *, "[ERR] hr <~ 0", ie, hr, tc, tc0
! ! ! !         read(*,*)
! ! ! !       end if

      ur=qr/sr !div_by_except_0(qr,sr)
      ul=qr/sr !div_by_except_0(ql,sl)

      !write(*,*) pl,pr
      !call sw_hll_dof(mesh,dof,flux,ie)
      !call sw_hll_u(mesh,hl,sl,ql,ul,hr,sr,qr,ur,flux,ie) !Send computed flux at the cell ie
      call sw_hll(mesh,hl,sl,ql,pl,hr,sr,qr,pr,flux,ie) !Send computed flux at the cell ie
      !call sw_rusanov(mesh,hl,sl,ql,hr,sr,qr,flux,ie) !Send computed flux at the cell ie
      !call sw_lax(mesh,hl,sl,ql,hr,sr,qr,flux,ie) !Send computed flux at the cell ie
      
!       if (ie == 3) then
!         print *, "LEFT_RIGHT:2"
!         print *, hl, hr
!         print *, sl, sr
!         print *, ql, qr
!         print *, "=>flux1=", flux(1)
!         print *, "=>flux2=", flux(2)
!       end if
!       
      tflux1(ie)=flux(1)  ! Aggregation of result to Sflux
      tflux2(ie)=flux(2)  ! Aggregation of result to Qflux

      !tflux1(ie)  = Fjm1d2
      !tflux1(ie+1)= Fjp1d2

   end do

   tflux1(1)=dof%q(1)
   tflux1(2)=dof%q(1)
   tflux1(3)=dof%q(1)

   !===================================
   !  Unknow computation  
   !===================================
   do ie = 3,mesh%ncs+2

      s=dof%s(ie)
      q=dof%q(ie)

      !======================================
      !  S,Q computation without source term
      !======================================      
      dof%s(ie)=max(0._rp,s-(dt/mesh%crosssection(ie)%delta)*(tflux1(ie+1)-tflux1(ie) )) !S computation without source term
      


      if (dof%S(ie).gt.zerom) then ! if gt.0_rp problem of >10-16
         dof%q(ie)=q-(dt/mesh%crosssection(ie)%delta)*(tflux2(ie+1)-tflux2(ie))          !Q computation without source term
      else
         dof%q(ie)=0._rp
         dof%s(ie)=0._rp
      end if
!       if (ie == 3) then
!         print *, "tflux1(4-3)=", tflux1(ie+1), tflux1(ie), dof%s(ie)
! !         read(*,*)
!       end if
!       if (ie == 3) then
!         print *, "tflux2(4-3)=", tflux2(ie+1), tflux2(ie), dof%q(ie)
! !         read(*,*)
!       end if
!       if (ie == 4) then
!         print *, "tflux2(5-4)=", tflux2(ie+1), tflux2(ie), dof%q(ie)
!       end if
!       if (ie == mesh%ncs+2) then
!         print *, "tflux2(end)=", tflux2(ie+1), tflux2(ie), dof%q(ie)
!         read(*,*)
!       end if
!       
   

      call UpdateMVectorElement(mesh,dof,ie,mvector)                 ! Update of mvector 
      call SurfaceToHeightCrossSection(mesh,dof,ie,mvector)          ! Update of dof%h(ie)
      call computationSgCrossSection(mesh,dof,sgie,ie,mvector)       ! Update of Sgie

      if (friction.eq.1) then 
         call computationRhCrossSection(mesh,dof,hydraulicRadiusie,ie,mvector) !Hydraulics computation (if friction==1)
      endif

      !dz/dx=(z(ie+1)-z(ie))/2dx
      dz = (bathy_cell(ie+1)-bathy_cell(ie-1))&
           /(mesh%crosssection(ie+1)%deltademi+mesh%crosssection(ie)%deltademi) !Slope computation
!       dz=mesh%crosssection(ie)%slope
!       if (ie == 3 .or. ie==4) then
!         print *, ie, dz
!         read(*,*)
!       end if

      s=dof%s(ie)
      q=dof%q(ie)

      SourceTermB     = sgie                          !Pressure       term
      SourceTermPente =-g*dz*S                        !Slope          term

      !===================================================
      !  S,Q computation with source term (friction)
      !===================================================
      if (friction.eq.1) then 
         if (s.gt.0) then
            call calc_K_at_cs(dof, Manning, ie)                  ! Update of Manning
            A=(q*abs(q))/(((Manning**2))*(s)*(hydraulicRadiusie**d4p3))   ! Sf= |q|*q /(K^2*S*Rh^(4/3)                
            SourceTermFriction=-g*A

         else 
            SourceTermFriction=0._rp
         end if 
      else 
         SourceTermFriction=0._rp
      end if


      SourceTerm      = SourceTermPente+SourceTermB+SourceTermFriction   !Pressure+slope term+Friction Term
   
      dof%sf(ie)          = SourceTermFriction

      dof%sg(ie)          = SourceTermPente+SourceTermB
      
	  !===================================================
      !  S,Q computation with source term (lateral inflow)
      !===================================================
	 ! if (lateral_flow.eq.1) then 
	    !  if (s.gt.0) then
        !	dof%s(ie) = dof%s(ie) + dt*qlat_masse ! q_lat_masse (check unités, q_lat (m3/s)/width/dx --> m/s
	     !  dof%q(ie) = dof%q(ie) + dt*qlat_qdm
		 ! end if 
	 ! end if

      !===================================================
      !  S,Q computation with source term (pressure+slope)
      !===================================================
      dof%q(ie)=q+dt*SourceTerm
!       if (ie == 3) then
!         print *, "Q+ ", ie, q , dt*SourceTerm, dof%q(ie)
!         print *, "++++ ", SourceTermPente, SourceTermB, SourceTermFriction
!       end if
!       if (ie == 4) then
!         print *, "Q+ ", ie, q , dt*SourceTerm, dof%q(ie)
!         print *, "++++ ", SourceTermPente, SourceTermB, SourceTermFriction
!         read(*,*)
!       end if

      !===================================================
      !  S,Q computation with source term (lateral inflow)
      !===================================================   
      select case( lat_inflow )
	  case ('1')

	  B = dof%s(ie)/dof%h(ie)
	  dx = mesh%CrossSection(ie+1)%coord%x - mesh%CrossSection(ie)%coord%x

		  if (s.gt.0) then
		    if ( ANY( bc%hyd_lat%loc == ie ) ) then
		    iloc=iloc+1
		    qlat = dof%qlat(1,iloc) !in m3/s

		    qlat_mass = qlat / dx
                    !print*,qlat_mass,qlat,dx
		    dof%s(ie) = dof%s(ie) + qlat_mass * dt 

		    ulat = (dof%q(ie) / dof%s(ie)) * qlat / (qlat + dof%q(ie) / B)

		    
		    qlat_qdm = qlat_mass * ulat !in m3.s-2
                    !print*,qlat_qdm,qlat_mass,ulat
		    dof%q(ie) = dof%q(ie) + qlat_qdm * dt


		    endif
		  endif

      end select

   end do


END SUBROUTINE euler_time_step_first
