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
!> \file euler_time_step_first_b2.f90
!! \brief This file includes the computation with HLL method with MUSCL slope limiter. An unique subroutine :
!! euler_time_step_first

!> Subroutine of the computation with HLL method with MUSCL and  slope limiter.
!!
!! \details Algorithm used:
!!
!!     Update boundaries conditions
!!     Update mvector
!!     Update pressure
!!
!!     do i = 2, n:
!!       Computation of MUSCL variables with slope limiter on h and u
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
SUBROUTINE euler_time_step_first_b2( dof , mesh )

   USE m_common
   USE m_mesh
   USE m_time_screen    
   USE m_model
   USE m_numeric

   implicit none

!======================================================================================================================!
!  Interface Variables
!======================================================================================================================!

   type( msh ), intent(in   )  ::  mesh

   type( unk ), intent(inout)  ::  dof

!======================================================================================================================!
!  Local Variables
!======================================================================================================================!

   real(rp)  :: hm2,hm1,h,hp1,hp2   !Height    at the point i-2,i-1,i,i+1,i+2

   real(rp)  :: qm2,qm1,q,qp1,qp2   !Flow      at the point i-2,i-1,i,i+1,i+2

   real(rp)  :: sm2,sm1,s,sp1,sp2   !Surface   at the point i-2,i-1,i,i+1,i+2

   real(rp)  :: um2,um1,u,up1,up2   !Velocity  at the point i-2,i-1,i,i+1,i+2

   real(rp)  :: zm2,zm1,z,zp1,zp2   !Elevation at the point i-2,i-1,i,i+1,i+2

   real(rp) :: xm1demiMxm1,xm1demiMxm3demi,xm1demiMx,xp1demiMxm1demi                   ! Deltax value  
   
   real(rp) ::deltaxm1demi, deltax,deltaxm1                                            !  Deltax and Deltax1demi

   real(rp) :: deltahath,deltahathm1,sigmah,sigmahm1,deltah,deltahm1,hm1demim,hm1demip ! Delta and sigma h for h reconstruction

   real(rp) :: deltahatu,deltahatum1,sigmau,sigmaum1,deltau,deltaum1,um1demim,um1demip ! Delta and sigma u for u reconstruction

   real(rp)  :: sl,sr ! Surface  to the cell left and right

   real(rp)  :: ul,ur ! Velocity to the cell left and right

   real(rp)  :: ql,qr ! Flow     to the cell left and right

   real(rp)  :: hl,hr ! Height   to the cell left and right
   
   real(rp)  :: dz    ! Local slope

   real(rp)  :: A  ,B ! Temporary variable

   real(rp)  ::  flux(2)                              ! Temporary flux ( output of hhl_m function)

   !real(rp), dimension( 2, mesh%ncs+4 )  ::  tflux    ! Vector total flux (aggregation of flux)

   real(rp)  :: Manning                               ! Value of Manning

   integer(ip), dimension(mesh%ncs+4) :: mVector              ! Pressure for fluxes computing
   
   real(rp) :: SourceTerm,SourceTermB,SourceTermPente,SourceTermFriction ! Sources termes (Total source terme, slope source term, and Pressure Source term)
   
   real(rp) :: alphab                                 ! Alpha (For MUSCL Reconstruction)

   real(rp) :: zm1demi                                ! Value of z to the interface between cell i-1 and i

   real(rp) :: deltaxm,deltaxp                        ! DeltaX at cell i-1, DeltaX at cell i+1

   real(rp)  :: sgie                                  ! Pressure source term at the cell ie

   real(rp)  :: hydraulicRadiusie                     ! Hydraulic Radius at the cell ie
   
   logical  :: elevationReconstruction                ! Boolean True -> Reconstruction on H, False -> Reconstruction on h

   real(rp) :: HtoSInterface_h,HtoSInterface                        ! Transformation of H to S to the interface between two cell
!======================================================================================================================!
!  Begin Subroutine
!======================================================================================================================!

   call calc_boundary_state( mesh,dof)
   
   call UpdateMVector(mesh,dof,mvector)         ! Update mvector   
   do ie= 3,mesh%ncs+3

      !===================================
      !  variable definition  
      !===================================

      zm2 =bathy_cell(ie-2)      
      zm1 =bathy_cell(ie-1)
      z   =bathy_cell(ie  )
      zp1 =bathy_cell(ie+1)

      hm2 =dof%h(ie-2) + zm2
      hm1 =dof%h(ie-1) + zm1
      h   =dof%h(ie  ) + z
      hp1 =dof%h(ie+1) + zp1

      qm2 =dof%q(ie-2)
      qm1 =dof%q(ie-1)
      q   =dof%q(ie  )
      qp1 =dof%q(ie+1)

      sm2 =dof%s(ie-2)      
      sm1 =dof%s(ie-1)
      s   =dof%s(ie  )
      sp1 =dof%s(ie+1)

      deltaxm1     = mesh%crosssection(ie-1)%delta
      deltax       = mesh%crosssection(ie)%delta
      deltaxm1demi = mesh%crosssection(ie)%deltademi

      um2 =div_by_except_0(qm2,sm2)
      um1 =div_by_except_0(qm1,sm1)
      u   =div_by_except_0(q  ,s )
      up1 =div_by_except_0(qp1,sp1)



      !===================================
      !  Interface value + MUSCL (see doc)
      !===================================

   
      alphab=one
      xm1demiMxm1=demi*deltaxm1demi
      xm1demiMxm3demi=deltaxm1

      xm1demiMx=-xm1demiMxm1
      xp1demiMxm1demi=deltax

      !  deltahat computing
      deltahath=demi*(hp1-hm1)
      deltahathm1=demi*(h-hm2)

      deltahatu=demi*(up1-um1)
      deltahatum1=demi*(u-um2)


      !  sigma computing
      sigmah   = div_by_except_0(deltahath  ,abs(deltahath  ))
      sigmau   = div_by_except_0(deltahatu  ,abs(deltahatu  ))
      sigmahm1 = div_by_except_0(deltahathm1,abs(deltahathm1))
      sigmaum1 = div_by_except_0(deltahatum1,abs(deltahatum1))
      
      !  deltah computing
      deltah  =sigmah  *max(zero, min(sigmah  *alphab*(h  -hm1),abs(deltahath  ),sigmah  *alphab*(hp1-h  )))  
      deltahm1=sigmahm1*max(zero, min(sigmahm1*alphab*(hm1-hm2),abs(deltahathm1),sigmahm1*alphab*(h  -hm1)))  
      deltau  =sigmau  *max(zero, min(sigmau  *alphab*(u  -um1),abs(deltahatu  ),sigmau  *alphab*(up1-u  )))  
      deltaum1=sigmaum1*max(zero, min(sigmaum1*alphab*(um1-um2),abs(deltahatum1),sigmaum1*alphab*(u  -um1)))  
 


      !  hm1demim & hm1demip
      deltaxm=(xm1demiMxm1)/(xm1demiMxm3demi)
      deltaxp=(xm1demiMx  )/(xp1demiMxm1demi)

      hm1demim=hm1 + deltahm1*deltaxm
      hm1demip=h   + deltah  *deltaxp

      um1demim=um1 + deltaum1*deltaxm
      um1demip=u   + deltau  *deltaxp

      !===================================
      !  transformation (h,u) to (S,Q) 
      !===================================


      Sl=HtoSInterface(mesh,ie-1,ie,hm1demim)
      Sr=HtoSInterface(mesh,ie-1,ie,hm1demip)


      !write(*,*) 'h-1,h-1d2-,h-1d2+,h ', hm1, hm1demim,hm1demip,h
      
      zm1demi=demi*(zm1+z)
      hm1demim=max(zero,hm1demim-zm1demi) 
      hm1demip=max(zero,hm1demip-zm1demi)
         
      Ql=sl*um1demim
      Qr=sr*um1demip

      call sw_hll_m(mesh,hm1demim,Sl,Ql,hm1demip,Sr,Qr,flux,ie)


      tflux1(ie)=flux(1)

      !if (ie.eq.3) then
      !   tflux1(ie)=dof%q(1) !linear_interp( bc%hyd%t ,bc%hyd%q ,tc) !65.0_rp
      !end if

      tflux2(ie)=flux(2)
   end do

   
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
      call UpdateMVectorElement(mesh, dof, ie, mvector)
      
      call SurfaceToHeightCrossSection(mesh,dof,ie,mvector)      !Update of dof%h(ie)
      call computationSgCrossSection(mesh,dof,sgie,ie,mvector)   !Update of Sgie

      if (friction.eq.1) then 
         !call computationRhCrossSection(mesh,dof,hydraulicRadiusie,ie) !Hydraulics computation (if friction==1)
         call computationRhCrossSection(mesh,dof,hydraulicRadiusie,ie,mvector) !Hydraulics computation (if friction==1)
      endif

      !dz/dx=(z(ie+1)-z(ie))/2dx
      dz = (bathy_cell(ie+1)-bathy_cell(ie-1))/(mesh%crosssection(ie)%deltademi+mesh%crosssection(ie-1)%deltademi) !Slope computation
      
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
            A=q*abs(q)/(((Manning**2))*(s)*(hydraulicRadiusie**d4p3))   ! Sf= |q|*q /(K^2*S*Rh^(4/3)         
            SourceTermFriction=-g*A

         else 
            SourceTermFriction=0._rp
         end if 
      else 
         SourceTermFriction=0._rp
      end if


      SourceTerm      = SourceTermPente+SourceTermB+SourceTermFriction   !Pressure+slope term+Friction Term
   
      !===================================================
      !  S,Q computation with source term (pressure+slope)
      !===================================================
      dof%q(ie)=q+dt*SourceTerm
      
   end do

!   call updateW(mesh,dof)

END SUBROUTINE euler_time_step_first_b2
