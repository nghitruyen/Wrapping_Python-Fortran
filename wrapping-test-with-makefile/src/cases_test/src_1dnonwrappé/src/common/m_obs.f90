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
!> \file m_obs.f90
!! \brief This file includes m_obs module.
!! \details The file includes only m_obs module (see doc m_obs module).



!**********************************************************************************************************************!
!**********************************************************************************************************************!
!
!  Module using Tapenade generated Output Files in /tap directory
!
!**********************************************************************************************************************!
!**********************************************************************************************************************!

!> Module m_obs.
!!
!! \details This module includes the definition of the innovation vector. Moreover, it is in this module that the 
!! subroutine which compute cost function are defined.
MODULE m_obs

   USE m_common
   USE m_model

   implicit none

   !> Structure of innovation_obs vector
   !!
   !! \details This structure include all observation parameters ( number of time step, space step, time index and the 
   !! array of the difference between observation and computation.
   TYPE innovation_obs

      integer(ip) :: nb_dt                            !< Number total of observation in time 
      
      integer(ip) :: nb_dx                            !< Number total of observation in space (not used)

      integer(ip) :: ind_t                            !< Number of time iteration

      real(rp), dimension(:), allocatable  ::  diff   !< Array of diff vector

   END TYPE innovation_obs

   type( innovation_obs ), dimension(:), allocatable  ::  innovation

   integer(ip)  ::  nb_obs !< Number of observation 

   integer(ip)  ::  nb_grp !< Number of observation group

   integer(ip)  ::  iobs   !< Iteration of observation
      
   real(rp) :: cost_obs, cost_regul         !< the 2 parts of the cost functions used as buffers to "trick" tapenade
   real(rp), dimension(4) :: cost_regul_parts         !< the 2 parts of the cost functions used as buffers to "trick" tapenade

   real(rp) :: recalc_alpha_regul !< if positive, recomputes the regularization coeff

   real(rp) :: alpha_regul !< bathy regularization weighing coeff

CONTAINS

!**********************************************************************************************************************!
!**********************************************************************************************************************!
!
!  Calculation of the cost function using model produced innovation vector
!
!**********************************************************************************************************************!
!**********************************************************************************************************************!

   !> Calculation of the cost function using model produced innovation vector
   !!
   !! \details The cost function is the sum of 3 terms: 
   !!    - The sum of the diff of the innonvation vector.
   !!    - The bathymetry regularization term.
   !!    - The hydograph regularization term.
   !!
   !! \param[inout] cost Value of the cost function.
   !! \param[in] mesh Mesh structure.
   SUBROUTINE calc_cost_function( cost , mesh )
      
      implicit none

      !================================================================================================================!
      !  Interface Variables
      !================================================================================================================!

      type( msh ), intent(in)  ::  mesh
      real(rp), intent(inout)  ::  cost

      !================================================================================================================!
      !  Local Variables
      !================================================================================================================!

      real(rp)  ::  J_obs, J_reg, J_reg_part(4)
      integer(ip)  ::  idiff
      ! TMP
      real(rp) :: err_model_2_obs, noise_2
      integer(ip) :: nb_obs_pts
      
      external update_regul_coeff_if_asked      
      
         if ( use_obs == 1 ) then

            ! TMP
            err_model_2_obs = 0.0_rp
            noise_2 = 0.0_rp
            nb_obs_pts = 0_ip
            
            !====================================================================================!
            !  Initialisation to zero of each part of the cost function
            !====================================================================================!

            J_obs =  0._rp
            J_reg_part(:) = 0._rp

            !====================================================================================!
            !  Compute J_obs = ||O^{-1/2}(H(u)-z)|| -> Loop on observations in Time/Space
            !====================================================================================!
            
            do iobs = 1,size( station )
               do idiff = 1,size( innovation( iobs )%diff )
            
                  J_obs  =  J_obs  +  station( iobs )%weight * innovation( iobs )%diff( idiff )**2
                  ! TMP
                  err_model_2_obs = err_model_2_obs + innovation( iobs )%diff( idiff )**2
                  noise_2 = noise_2 + 1.0 / station( iobs )%weight
                  nb_obs_pts = nb_obs_pts + 1
                  
               end do
            end do
            cost_obs = J_obs ! used to compute an adaptative alpha_regul

            ! TMP
            err_model_2_obs = err_model_2_obs / nb_obs_pts
            noise_2 = noise_2 / nb_obs_pts
          
#ifdef DEBUG
            if (cost_obs > 1e+12) then
               print *, "COST !!!!!", cost_obs
               open(54, file="min/cost_obs_detail.txt")
               do iobs = 1,size( station )

                  do idiff = 1,size( innovation( iobs )%diff )
               
                     write(54, '(I8,I8,E12.5)') iobs, idiff, innovation( iobs )%diff( idiff )
                  end do
               end do
               close(54)
               read(*,*)
            end if
#endif

            !==========================================================================================================!
            !  Compute J_reg, the regularization term
            !==========================================================================================================!
            !====================================================================================!
            !  Bathymetry regularization term
            !====================================================================================!

            call calc_bathy_regularization_term( mesh, J_reg_part(1) )
         
            !=====================================================================================!
            !  Hydograph Regularization Term
            !=====================================================================================!
               
            call calc_hydro_regularization_term( mesh, J_reg_part(2) )
            
            
            !=====================================================================================!
            ! Hydograph Lat Regularization Term
            !=====================================================================================!

            do j = 1,size(bc%hyd_lat%q(:,1))!nb of lat hydrographs
	       call calc_hydrolat_regularization_term( mesh, J_reg_part(4) )
	    enddo

            !=====================================================================================!
            !  Strickler Regularization Term
            !=====================================================================================!
               
            call calc_strickler_regularization_term( mesh, J_reg_part(3) )
                       
            !=====================================================================================!
            !  Calc Regularization Term
            !=====================================================================================!
               
            J_reg = sum( J_reg_part )
            cost_regul = J_reg  ! used to compute an adaptative alpha_regul
            cost_regul_parts(:) = J_reg_part
 
            ! Update regularization weihghing coeff, hidden from tapenade so it is seen as "constant"
!             print *, "HERE !!!!!!!!!!"
            CALL update_regul_coeff_if_asked(alpha_regul, recalc_alpha_regul, J_obs, J_reg)
!             alpha_regul = 1

            !<NODAJ
!             print*, "Jobs = ", J_obs, ", Jreg = ", J_reg
!             print*, 'err_model_2_obs', err_model_2_obs, noise_2
!             print*, 'nb_obs_pts', nb_obs_pts
!             print*, 'gamma_noise', err_model_2_obs / noise_2
!             print*, 'cost_obs', cost_obs, 'cost_regul', cost_regul
! !              if (regul_bathy > 1e-12) then
!                 !print*, "Jreg_bathy =", J_reg_part(1), "Jreg_hydro =", J_reg_part(2), "Jreg_strickler =", J_reg_part(3)
! !              end if
             !>NODAJ

            !=====================================================================================!
            !  Sum of each part
            !=====================================================================================!
!             print *, "REGUL:", alpha_regul, J_obs, alpha_regul*J_reg
            cost = J_obs + alpha_regul*J_reg

         end if

      !===========================================================================================!
      !  Fake operation for Tapenade Automatic Differentiation (Last operation ...)
      !===========================================================================================!

         cost = sqrt( cost**2 )

       END SUBROUTINE calc_cost_function



       
       !> Calculation of the bathymetry-related regularization term
       !!
         !! \details .
       SUBROUTINE calc_bathy_regularization_term(mesh, J_reg_bathy)

         implicit none
         
         type( msh ), intent(in)  ::  mesh
         real(rp), intent(inout) :: J_reg_bathy
         real(rp), dimension( mesh%ncs+4 ) :: delta_bathy
         real(rp) :: dbdx_mean, dbdx1, dbdx2, correl, dx, h0b_mean
         real(rp) :: mu1, mu2

            select case ( bathy_regul_type )
               
            case('bayes')
               regul_bathy = 1
               if ( var_chg ) then
                  if ( c_bathy == 1 ) then
                     do i = 1, nb_bathy_control_pts
                        J_reg_bathy = J_reg_bathy + bathy_points_chg(i)**2
                     end do
                  else if ( c_bathy == 3 ) then
                     ! if change of variables done, J_reg = ||v||^2 -> No need to calc B^{-1}
                     do i = 1,nb_bathy_control_pts
                        J_reg_bathy = J_reg_bathy + bathy_cell_chg(i)**2
                     end do
                  end if
               else
                  ! A TERMINER
                  J_reg_bathy = 0._rp
!!$                 ! ||B^{-1/2}*(zb-zb_fg)||_L2^2, with B the cov matrix of the bathy background error
!!$                 if ( .not. allocated( Bdemi_bathy_inv ) ) call calc_inv_cov_matrix() ! /!\ NOT IMPLEMENTED YET                 
!!$                 do i = bathy_first,bathy_last,bathy_step
!!$                    delta_bathy(i) = bathy_cell(i) - mesh%crosssection(i)%elevation
!!$                 end do
!!$                 ! Jreg = Jreg + (zb_zb_fg)^T*B^{-1}*(zb_zb_fg)
!!$                 J_reg_bathy = J_reg_bathy + &
!!$                      dot_product( MATMUL(MATMUL(Bdemi_bathy_inv,Bdemi_bathy_inv),delta_bathy(bathy_first,bathy_last,bathy_step)) , delta_bathy(bathy_first,bathy_last,bathy_step) )
               end if
               
            case('z-z0')
               ! L2-norm of zb-zb_fg (fg = first guess)
               j = 1
               do i = bathy_first,bathy_last,bathy_step
                  delta_bathy(i) = bathy_cell(i) - bathy_cell_fg(j)
                  J_reg_bathy = J_reg_bathy + delta_bathy(i)**2
                  j = j+1
               end do

            case ( 'grad' )
               ! L2-norm of the 1st derivative of the bathymetry (at each point !)                 
               do i = 3,mesh%ncs+1
                  J_reg_bathy = J_reg_bathy + &
                       ( (bathy_cell(i+1) - bathy_cell(i)) / mesh%crosssection(i+1)%deltademi )**2
               end do

            case ( 'laplacian' )
               ! norme L2 of the 2nd derivative of the bathymetry (at each point !) 
               do i = 3,mesh%ncs+1
                  J_reg_bathy = J_reg_bathy + &
                       ( (bathy_cell(i+1) + bathy_cell(i-1) - 2*bathy_cell(i)) / mesh%crosssection(i)%delta**2 )**2
!                   print *, bathy_cell(i-1), bathy_cell(i), bathy_cell(i+1)
               end do

            case ( 'weighted_h2_sobolev_norm' )
               ! Weighted H2-norm : ||f||^2_H2 = ||f||^2+mu1*||f'||^2+mu2*||f''||^2, with f=zb-zb_fg
               ! /!\ at each point !
               ! Coeff to be defined to set the correlation -> can be sraightforward achieved by using
               mu1 = 1._rp
               mu2 = 1._rp 
               do i = 3,mesh%ncs+2
                  delta_bathy(i) = bathy_cell(i) - mesh%crosssection(i)%elevation
               end do
               do i = 4,mesh%ncs+1
                  J_reg_bathy = J_reg_bathy + &
                       delta_bathy(i)**2 +&
                       mu1*( (delta_bathy(i+1) - delta_bathy(i)) / mesh%crosssection(i+1)%deltademi )**2 + &
                       mu2*( (delta_bathy(i+1) + delta_bathy(i-1) - 2*delta_bathy(i)) / mesh%crosssection(i)%delta**2 )**2
               end do

            case ('smoothing')
               ! Introduce manually some correlation between the bathy pts (Kevin)
               dbdx_mean = 0.0
               do i = 2,mesh%ncs+3
                  dbdx1 = (bathy_cell(i+1)-bathy_cell(i-1))/(mesh%crosssection(i+1)%deltademi + mesh%crosssection(i)%deltademi)
                  dbdx_mean = dbdx_mean + abs(dbdx1) / (mesh%ncs+3-2+1)
                  dx = 0.0
                  j = i - 1
                  do while (dx < 600.0)
                     j = j + 1
                     if (j > mesh%ncs+3) exit
                     dx = dx + mesh%crosssection(j)%deltademi
                     correl = 0.5 / pi * exp(-0.5 * (abs(dx) / 200.0)**2)
                     dbdx2 = (bathy_cell(j+1)-bathy_cell(j-1))/&
                          (mesh%crosssection(j+1)%deltademi + mesh%crosssection(j)%deltademi)
                     J_reg_bathy = J_reg_bathy + correl * abs(dbdx2 * dbdx1)

                  end do
                  dx = 0.0
                  j = i
                  do while (dx < 600.0)
                     j = j - 1
                     if (j < 2) exit
                     dx = dx + mesh%crosssection(j)%deltademi
                     correl = 0.5 / pi * exp(-0.5 * (abs(dx) / 200.0)**2)
                     dbdx2 = (bathy_cell(j+1)-bathy_cell(j-1))/&
                          (mesh%crosssection(j+1)%deltademi + mesh%crosssection(j)%deltademi)
                     J_reg_bathy = J_reg_bathy + correl * abs(dbdx2 * dbdx1)
                  end do
               end do
               J_reg_bathy = J_reg_bathy / dbdx_mean**2

            case('tikhonov_h0')
            
               print *, "bathy_regul_type 'tikhonov_h0' is deprecated"
               stop
               ! h0-h0_fg_mean (interet ?? -> ask Kevin)
               h0b_mean = 0._rp
               do i = 2,mesh%ncs+3
                  h0b_mean = h0b_mean + (mesh%crosssection(i)%height(1) - mesh%crosssection(i)%elevation)**2
                  J_reg_bathy = J_reg_bathy + &
                       (mesh%crosssection(i)%height(1) - bathy_cell(i))**2
               end do
               J_reg_bathy = J_reg_bathy / h0b_mean


            case default
               ! no regularization applied
               print*, 'no regularization for the bathymetry term' !NOADJ
               J_reg_bathy = 0._rp

            end select
         
         J_reg_bathy = J_reg_bathy * regul_bathy

       END SUBROUTINE calc_bathy_regularization_term


       !> Calculation of the hydrograph-related regularization term
       !!
       !! \details .
       SUBROUTINE calc_hydro_regularization_term(mesh, J_reg_hydro)

         implicit none
         
         type( msh ), intent(in)  ::  mesh
         real(rp), intent(inout) :: J_reg_hydro

         select case ( hydro_regul_type )
               
         case('bayes')
            regul_hydrograph = 1 ! to be consistent with the use of Bdemi (if regul_hydrograph=0 with the use of a bayes regul, it is as if Bdemi=infinity != Bdemi specified)
            if ( var_chg ) then
               do i = 1,size(bc%hyd%q)
                  J_reg_hydro = J_reg_hydro + qin_chg(i)**2
               end do
            else
            J_reg_hydro = 0._rp
            ! A TERMINER
            ! ||B^{-1/2}*(Qin-Qin_fg)||_L2^2, with B the cov matrix of the hydro background error
!!$           if ( .not. allocated( Bdemi_hydro_inv ) ) call calc_inv_cov_matrix() ! /!\ NOT IMPLEMENTED YET /!\
!!$              do i = bathy_first,bathy_last,bathy_step
!!$                 delta_bathy(i) = bathy_cell(i) - mesh%crosssection(i)%elevation
!!$              end do
!!$              ! Jreg = Jreg + (zb_zb_fg)^T*B^{-1}*(zb_zb_fg)
!!$              J_reg_bathy = J_reg_bathy + &
!!$                   MATMUL(delta_bathy(bathy_first,bathy_last,bathy_step),MATMUL(MATMUL(B_inv_demi_bathy,B_inv_demi_bathy),delta_bathy(bathy_first,bathy_last,bathy_step)))
!!$
         end if

         case default
            J_reg_hydro = 0._rp
         end select
         
         J_reg_hydro = J_reg_hydro*regul_hydrograph
         
       END SUBROUTINE calc_hydro_regularization_term

      SUBROUTINE calc_hydrolat_regularization_term(mesh, J_reg_hydrolat) !TODO : add regul_hydrograph_lat(:) ?

         implicit none
         
         type( msh ), intent(in)  ::  mesh
         real(rp), intent(inout) :: J_reg_hydrolat
         
         regul_hydrographlat = bc%hyd_lat%params(j,3)    

         select case ( hydro_regul_type )
                
         case('bayes')
            regul_hydrographlat = 1 ! to be consistent with the use of Bdemi (if regul_hydrograph=0 with the use of a bayes regul, it is as if Bdemi=infinity != Bdemi specified)
            if ( var_chg ) then
               do i = 1,size(bc%hyd_lat%q(1,:))
                  J_reg_hydrolat = J_reg_hydrolat + qlat_chg(j,i)**2
               end do
            else
            J_reg_hydrolat = 0._rp
         end if

         case default
            J_reg_hydrolat = 0._rp
         end select
         
         J_reg_hydrolat = J_reg_hydrolat*regul_hydrographlat

       END SUBROUTINE calc_hydrolat_regularization_term



       !> Calculation of the strickler-related regularization term
       !!
       !! \details .
       SUBROUTINE calc_strickler_regularization_term(mesh, J_reg_strickler)

         implicit none
         
         type( msh ), intent(in)  ::  mesh
         real(rp), intent(inout) :: J_reg_strickler

         select case ( strickler_regul_type )
               
         case('bayes')
            regul_manning = 1
            if ( var_chg ) then
               do i = 1,K_params%nb_diff_K_reachs
                  J_reg_strickler = J_reg_strickler + alpha_K_chg(i)**2
                  J_reg_strickler = J_reg_strickler + beta_K_chg(i)**2
               end do
            else
               J_reg_strickler = 0._rp
            end if

         case default
            J_reg_strickler = 0._rp

         end select
         
         J_reg_strickler = J_reg_strickler*regul_manning
         
       END SUBROUTINE calc_strickler_regularization_term













       
















    



!**********************************************************************************************************************!
!**********************************************************************************************************************!
!
!  Calculation of the cost function directly updating its value during simulation (no observations)
!
!**********************************************************************************************************************!
!**********************************************************************************************************************!

   !> Calculation of the cost function directly updating its value during simulation (no observations)
   !!
   !! \details This subroutine fone the computation of the cost function directly from value of vector dof during
   !! simulation (without obsevations).
   !!
   !! \param[in] dof Unknowns (h,s,q).
   !! \param[inout] cost Value of the cost function.
   SUBROUTINE update_cost_function( dof , cost )

      implicit none

      !================================================================================================================!
      !  Interface Variables
      !================================================================================================================!

      type( unk ), intent(in)  ::  dof

      real(rp), intent(inout)  ::  cost

      !================================================================================================================!
      !  Local Variables
      !================================================================================================================!

      integer(ip)  ::  cell , pt

      real(rp)  ::  h_mean,q_mean

      !================================================================================================================!
      !  Begin
      !================================================================================================================!
         do iobs = 1,size( station )

            if ( .not. test_dt_just_after( station( iobs )%dt ) ) cycle

            h_mean = 0._rp

            do pt = 1,size( station( iobs )%pt )

               cell = station( iobs )%pt( pt )%indexi

               if ( cell < 0 ) cycle

               h_mean = h_mean + dof%h( cell )! COST_CHANGE
               !h_mean = h_mean + dof%h( cell )!+bathy_cell(cell)
               !q_mean  = q_mean + dof%q( cell )
            end do

            h_mean = h_mean / real( size( station( iobs )%pt ) , 8 )
            q_mean = q_mean / real( size( station( iobs )%pt ) , 8 )

            cost = cost + station( iobs )%weight * h_mean**2
         
         end do


   END SUBROUTINE update_cost_function
   

END MODULE m_obs

    !**********************************************************************************************************************!
    !
    !  Calculation of the regularization coefficient that may vary throughout the descent algorithm
    !
    !**********************************************************************************************************************!

    !> Compute the regularization coefficient that may vary throughout the descent algorithm
    !! 
    !! \details Compute the regularization coefficient alpha_regul used in J = Jobs + alpha_regul * Jreg. 
    !!          So far, it is computed as the value of Jobs/Jreg ratio
    !! \param[in,out] alpha_regul Regularization coefficient (in J = Jobs + alpha_regul * Jreg)
    !! \param[in,out] recalc_alpha_regul Recomputation flag (recalc_alpha_regul > 0 update, otherwise do nothing)
    !<NOADJ
SUBROUTINE update_regul_coeff_if_asked(alpha_regul, recalc_alpha_regul, Jobs, Jreg)
  use m_common, only : rp
  use m_obs, only : cost_obs, cost_regul, regul_gamma
      implicit none
      !  Interface Variables
      real(rp), intent(inout)  ::  alpha_regul
      real(rp), intent(inout)  :: recalc_alpha_regul  ! used as an interface variable because its value is changed in the routine, and since we want to use the same value for the main routine and for the diff and back routines, it is necessary to use it as an interface variable so Tapenade can push/pop its value when using the back and diff routines
      real(rp), intent(inout)  :: Jobs
      real(rp), intent(inout)  :: Jreg
      ! Calc alpha_regul
      if (recalc_alpha_regul > 0.0) then
!          alpha_regul = regul_bathy*cost_obs/cost_regul
         if (abs(Jreg) < 1e-12) then
            alpha_regul = 0.0
         else
            alpha_regul = regul_gamma*Jobs/Jreg
         endif
!           print *, "update_regul_coeff_if_asked:", regul_gamma, alpha_regul
         recalc_alpha_regul = -1
      end if
      
    END SUBROUTINE update_regul_coeff_if_asked
! 
!     SUBROUTINE update_regul_coeff_if_asked_diff(alpha_regul, recalc_alpha_regul)
!         use m_common, only : rp
!       implicit none
!       !  Interface Variables
!       real(rp), intent(inout)  ::  alpha_regul, recalc_alpha_regul
!       ! Calc alpha_regul
!       call update_regul_coeff_if_asked(alpha_regul, recalc_alpha_regul)
!     END SUBROUTINE update_regul_coeff_if_asked_diff

    SUBROUTINE update_regul_coeff_if_asked_diff(alpha_regul, alpha_regul_diff,&
                                                recalc_alpha_regul, Jobs, Jobs_diff,&
                                                Jreg, Jreg_diff)
        use m_common, only : rp
      implicit none
      !  Interface Variables
      real(rp), intent(inout)  ::  alpha_regul, alpha_regul_diff
      real(rp), intent(inout)  ::  recalc_alpha_regul
      real(rp), intent(inout)  :: Jobs, Jobs_diff
      real(rp), intent(inout)  :: Jreg, Jreg_diff
      ! Calc alpha_regul
!       call update_regul_coeff_if_asked(alpha_regul, recalc_alpha_regul, Jobs, Jreg)
    END SUBROUTINE update_regul_coeff_if_asked_diff
! 
!     SUBROUTINE update_regul_coeff_if_asked_back(alpha_regul, recalc_alpha_regul)
!         use m_common, only : rp
!       implicit none
!       !  Interface Variables
!       real(rp), intent(inout)  ::  alpha_regul, recalc_alpha_regul
!       ! Calc alpha_regul
!       call update_regul_coeff_if_asked(alpha_regul, recalc_alpha_regul)
!     END SUBROUTINE update_regul_coeff_if_asked_back

    SUBROUTINE update_regul_coeff_if_asked_back(alpha_regul, alpha_regul_back,&
                                                recalc_alpha_regul, Jobs, Jobs_back,&
                                                Jreg, Jreg_back)
        use m_common, only : rp
      implicit none
      !  Interface Variables
      real(rp), intent(inout)  ::  alpha_regul, alpha_regul_back
      real(rp), intent(inout)  ::  recalc_alpha_regul
      real(rp), intent(inout)  :: Jobs, Jobs_back
      real(rp), intent(inout)  :: Jreg, Jreg_back
      ! Calc alpha_regul
      call update_regul_coeff_if_asked(alpha_regul, recalc_alpha_regul, Jobs, Jreg)
      recalc_alpha_regul = -1
    END SUBROUTINE update_regul_coeff_if_asked_back
    
    !>NOADJ
