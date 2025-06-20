! Copyright (C) 2001  Ernst Maier-Reimer
! Copyright (C) 2020  K. Assmann, J. Tjiputra, J. Schwinger
!
! This file is part of BLOM/iHAMOCC.
!
! BLOM is free software: you can redistribute it and/or modify it under the
! terms of the GNU Lesser General Public License as published by the Free
! Software Foundation, either version 3 of the License, or (at your option)
! any later version.
!
! BLOM is distributed in the hope that it will be useful, but WITHOUT ANY
! WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
! FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for
! more details.
!
! You should have received a copy of the GNU Lesser General Public License
! along with BLOM. If not, see https://www.gnu.org/licenses/.

module mo_hamocc4bcm

  implicit none
  private

  public :: hamocc4bcm

contains

  subroutine hamocc4bcm(kpie,kpje,kpke,kbnd,kplyear,kplmon,kplday,kldtday,pdlxp,pdlyp,pddpo,prho,  &
                        pglat,omask, dust,rivin,ndep,oafx,pi_ph,pfswr,psicomo,ppao,pfu10,ptho,psao,&
                        patmco2,pflxco2,pflxdms,patmbromo,pflxbromo,                               &
                        patmn2o,pflxn2o,patmnh3,pflxnh3,shelfmask)

    !***********************************************************************************************
    ! Main routine of iHAMOCC.
    !
    ! Modified:
    !  J.Schwinger       *GFI, Bergen*    2013-10-21
    !  - added GNEWS2 option for riverine input of carbon and nutrients
    !  - code cleanup
    !  J.Schwinger       *GFI, Bergen*    2014-05-21
    !  - moved copying of tracer field to ocetra to micom2hamocc and hamocc2micom
    !  J.Schwinger,      *Uni Research, Bergen*   2018-04-12
    !  - moved accumulation of all output fields to seperate subroutine, related code-restructuring
    !  - added sediment bypass preprocessor option
    !  J.Schwinger,      *NORCE Climate, Bergen*   2020-05-28
    !  - restructuring of iHAMOCC code, cleanup parameter list
    !  - boundary conditions (dust, riverinput, N-deposition) are now passed as an argument
    !***********************************************************************************************

    use mod_xc,           only: mnproc
    use mo_kind,          only: rp
    use mo_carbch,        only: atmflx,ocetra,atm,atm_cfc11_nh,atm_cfc11_sh,atm_cfc12_nh,          &
                                atm_cfc12_sh,atm_sf6_nh,atm_sf6_sh
    use mo_biomod,        only: strahl
    use mo_control_bgc,   only: ldtrunbgc,dtbgc,ldtbgc,io_stdo_bgc,dtbgc,ndtdaybgc,                &
                                do_sedspinup,sedspin_yr_s,sedspin_yr_e,sedspin_ncyc,               &
                                use_BROMO, use_CFC, use_PBGC_CK_TIMESTEP,                          &
                                use_BOXATM, use_sedbypass,ocn_co2_type,                            &
                                do_n2o_coupled,use_extNcycle,use_pref_tracers,                     &
                                use_shelfsea_res_time,do_nh3_coupled
    use mo_param1_bgc,    only: iatmco2,iatmdms,nocetra,nriv,iatmbromo,nndep,ndust,iatmn2o,iatmnh3
    use mo_vgrid,         only: set_vgrid
    use mo_apply_fedep,   only: apply_fedep
    use mo_apply_rivin,   only: apply_rivin
    use mo_apply_ndep,    only: apply_ndep
    use mo_apply_oafx,    only: apply_oafx
    use mo_boxatm,        only: update_boxatm
    use mo_inventory_bgc, only: inventory_bgc
    use mo_sedshi,        only: sedshi
    use mo_get_cfc,       only: get_cfc
    use mo_powach,        only: powach
    use mo_preftrc,       only: preftrc
    use mo_cyano,         only: cyano
    use mo_ocprod,        only: ocprod
    use mo_carchm,        only: carchm
    use mo_chemcon,       only: mw_nh3,mw_n2o
    use mo_shelfsea_restime,only: shelfsea_residence_time

    ! Arguments
    integer, intent(in)  :: kpie                                            ! 1st dimension of model grid.
    integer, intent(in)  :: kpje                                            ! 2nd dimension of model grid.
    integer, intent(in)  :: kpke                                            ! 3rd (vertical) dimension of model grid.
    integer, intent(in)  :: kbnd                                            ! number of halo grid points.
    integer, intent(in)  :: kplyear                                         ! current year.
    integer, intent(in)  :: kplmon                                          ! current month.
    integer, intent(in)  :: kplday                                          ! current day.
    integer, intent(in)  :: kldtday                                         ! number of time step in current day.
    real(rp),intent(in)  :: pdlxp  (kpie,kpje)                              ! size of grid cell (longitudinal) [m].
    real(rp),intent(in)  :: pdlyp  (kpie,kpje)                              ! size of grid cell (latitudinal) [m].
    real(rp),intent(in)  :: pddpo  (kpie,kpje,kpke)                         ! size of grid cell (depth) [m].
    real(rp),intent(in)  :: prho   (kpie,kpje,kpke)                         ! density [g/cm^3].
    real(rp),intent(in)  :: pglat  (1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! latitude of grid cells [deg north].
    real(rp),intent(in)  :: omask  (kpie,kpje)                              ! land/ocean mask.
    real(rp),intent(in)  :: dust   (kpie,kpje,ndust)                        ! dust/sFe deposition flux [kg dust m-2 s-1] and [kmol sFe m-2 s-1].
    real(rp),intent(in)  :: rivin  (kpie,kpje,nriv)                         ! riverine input [kmol m-2 yr-1].
    real(rp),intent(in)  :: ndep   (kpie,kpje,nndep)                        ! nitrogen deposition [kmol m-2 yr-1].
    real(rp),intent(in)  :: oafx   (kpie,kpje)                              ! alkalinity flux from alkalinization [kmol m-2 yr-1]
    real(rp),intent(in)  :: pi_ph  (kpie,kpje)                              ! pre-ind. pH climatology used for pH-dependent DMS fluxes [log10([H+])]
    real(rp),intent(in)  :: pfswr  (1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! solar radiation [W/m**2].
    real(rp),intent(in)  :: psicomo(1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! sea ice concentration
    real(rp),intent(in)  :: ppao   (1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! sea level pressure [Pascal].
    real(rp),intent(in)  :: pfu10  (1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! absolute wind speed at 10m height [m/s]
    real(rp),intent(in)  :: ptho   (1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd,kpke) ! potential temperature [deg C].
    real(rp),intent(in)  :: psao   (1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd,kpke) ! salinity [psu.].
    real(rp),intent(in)  :: patmco2(1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! atmospheric CO2 concentration [ppm] used in fully coupled mode
    real(rp),intent(out) :: pflxco2(1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! CO2 flux [kg/m^2/s].
    real(rp),intent(out) :: pflxdms(1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! DMS flux [kg/m^2/s].
    real(rp),intent(in)  :: patmbromo(1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)    ! atmospheric bromoform concentration [ppt] used in fully coupled mode.
    real(rp),intent(out) :: pflxbromo(1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)    ! Bromoform flux [kg/m^2/s].
    real(rp),intent(in)  :: patmn2o(1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! atmospheric nitrous oxide concentration [ppt] used in fully coupled mode.
    real(rp),intent(out) :: pflxn2o(1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! Nitrous oxide flux [kg N2O m-2 s-1].
    real(rp),intent(in)  :: patmnh3(1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! atmospheric ammonia concentration [ppt] used in fully coupled mode
    real(rp),intent(out) :: pflxnh3(1-kbnd:kpie+kbnd,1-kbnd:kpje+kbnd)      ! Ammonia flux [kg NH3 m-2 s-1].
    logical, intent(in)  :: shelfmask(kpie,kpje)                            ! mask for shelf sea regions (1=shelf, 0 elsewhere)

    ! Local variables
    integer :: i,j,k,l
    integer :: nspin,it
    logical :: lspin

    if (mnproc.eq.1) then
      write(io_stdo_bgc,*) 'iHAMOCC',KLDTDAY,LDTRUNBGC,NDTDAYBGC
    endif

    !--------------------------------------------------------------------
    ! Increment bgc time step counter of run (initialized in HAMOCC_INIT).
    !
    ldtrunbgc = ldtrunbgc + 1

    !--------------------------------------------------------------------
    ! Increment bgc time step counter of experiment.
    !
    ldtbgc = ldtbgc + 1

    !--------------------------------------------------------------------
    ! Calculate variables related to the vertical grid
    !
    call set_vgrid(kpie,kpje,kpke,pddpo)

    !--------------------------------------------------------------------
    ! Pass net solar radiation
    !
    !$OMP PARALLEL DO PRIVATE(i)
    do  j=1,kpje
      do  i=1,kpie
        strahl(i,j)=pfswr(i,j)
      enddo
    enddo
    !$OMP END PARALLEL DO

    !--------------------------------------------------------------------
    ! Pass atmospheric co2 if coupled to an active atmosphere model
    !
    if (trim(ocn_co2_type) == 'diagnostic' .or. trim(ocn_co2_type) == 'prognostic') then
      !$OMP PARALLEL DO PRIVATE(i)
      do  j=1,kpje
        do  i=1,kpie
          atm(i,j,iatmco2)=patmco2(i,j)
        enddo
      enddo
      !$OMP END PARALLEL DO
      !if (mnproc.eq.1) write (io_stdo_bgc,*) 'iHAMOCC: getting co2 from atm'
    endif

    if (use_BROMO) then
      !$OMP PARALLEL DO PRIVATE(i)
      do  j=1,kpje
        do  i=1,kpie
          if (patmbromo(i,j).gt.0._rp) then
            atm(i,j,iatmbromo)=patmbromo(i,j)
          endif
        enddo
      enddo
      !$OMP END PARALLEL DO
      if (mnproc.eq.1) write (io_stdo_bgc,*) 'iHAMOCC: getting bromoform from atm'
    endif

    if (use_extNcycle) then
      if (do_n2o_coupled) then
        !$OMP PARALLEL DO PRIVATE(i)
        do  j=1,kpje
          do  i=1,kpie
            if (patmn2o(i,j) > 0._rp) then
              atm(i,j,iatmn2o)=patmn2o(i,j)
            endif
          enddo
        enddo
        !$OMP END PARALLEL DO
        if (mnproc.eq.1) write (io_stdo_bgc,*) 'iHAMOCC: getting N2O conc. from atm'
      endif
      if (do_nh3_coupled) then
        !$OMP PARALLEL DO PRIVATE(i)
        do  j=1,kpje
          do  i=1,kpie
            if (patmnh3(i,j) > 0._rp) then
              atm(i,j,iatmnh3)=patmnh3(i,j)
            endif
          enddo
        enddo
        !$OMP END PARALLEL DO
        if (mnproc.eq.1) write (io_stdo_bgc,*) 'iHAMOCC: getting NH3 conc. from atm'
      endif
    endif

    !--------------------------------------------------------------------
    ! Read atmospheric cfc concentrations
    !
    if (use_CFC) then
      call get_cfc(kplyear,atm_cfc11_nh,atm_cfc12_nh,atm_sf6_nh,        &
           atm_cfc11_sh,atm_cfc12_sh,atm_sf6_sh)
    endif

    if (use_PBGC_CK_TIMESTEP) then
      if (mnproc.eq.1) then
        write(io_stdo_bgc,*)' '
        write(io_stdo_bgc,*)'before BGC: call INVENTORY'
      endif
      call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
    endif

    !---------------------------------------------------------------------
    ! Biogeochemistry
    !
    call ocprod(kpie,kpje,kpke,kbnd,pdlxp,pdlyp,pddpo,omask,ptho,pi_ph,psao,ppao,prho)

    if (use_PBGC_CK_TIMESTEP   ) then
      if (mnproc.eq.1) then
        write(io_stdo_bgc,*)' '
        write(io_stdo_bgc,*)'after OCPROD: call INVENTORY'
      endif
      call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
    endif

    do l=1,nocetra
      do K=1,kpke
        !$OMP PARALLEL DO PRIVATE(i)
        do J=1,kpje
          do I=1,kpie
            if (OMASK(I,J) .gt. 0.5_rp ) then
              OCETRA(I,J,K,L)=max(0._rp,OCETRA(I,J,K,L))
            endif
          enddo
        enddo
        !$OMP END PARALLEL DO
      enddo
    enddo

    if (use_PBGC_CK_TIMESTEP   ) then
      if (mnproc.eq.1) then
        write(io_stdo_bgc,*)' '
        write(io_stdo_bgc,*)'after LIMIT: call INVENTORY'
      endif
      call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
    endif

    call cyano(kpie,kpje,kpke,kbnd,pddpo,omask,ptho)

    if (use_PBGC_CK_TIMESTEP   ) then
      if (mnproc.eq.1) then
        write(io_stdo_bgc,*)' '
        write(io_stdo_bgc,*)'after CYANO: call INVENTORY'
      endif
      call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
    endif

    call carchm(kpie,kpje,kpke,kbnd,pdlxp,pdlyp,pddpo,prho,pglat,omask,psicomo,ppao,pfu10,ptho,psao)

    if (use_PBGC_CK_TIMESTEP   ) then
      if (mnproc.eq.1) then
        write(io_stdo_bgc,*)' '
        write(io_stdo_bgc,*)'after CARCHM: call INVENTORY'
      endif
      call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
    endif

    ! Apply dust (iron) deposition
    call apply_fedep(kpie,kpje,kpke,pddpo,omask,dust)

    ! Apply n-deposition
    call apply_ndep(kpie,kpje,kpke,pddpo,omask,ndep)

    if (use_PBGC_CK_TIMESTEP ) then
      if (mnproc.eq.1) then
        write(io_stdo_bgc,*)' '
        write(io_stdo_bgc,*)'after N deposition: call INVENTORY'
      endif
      call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
    endif

    ! Apply riverine input of carbon and nutrients
    call apply_rivin(kpie,kpje,kpke,pddpo,omask,rivin)

    if (use_PBGC_CK_TIMESTEP ) then
      if (mnproc.eq.1) then
        write(io_stdo_bgc,*)' '
        write(io_stdo_bgc,*)'after river input: call INVENTORY'
      endif
      call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
    endif

    ! Apply alkalinity flux due to ocean alkalinization
    call apply_oafx(kpie,kpje,kpke,pddpo,omask,oafx)

    if (use_PBGC_CK_TIMESTEP ) then
      if (mnproc.eq.1) then
        write(io_stdo_bgc,*)' '
        write(io_stdo_bgc,*)'after ocean alkalinization: call INVENTORY'
      endif
      call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
    endif

    ! Update atmospheric pCO2 [ppm]
    if (use_BOXATM) then
      call update_boxatm(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask)
    endif

    if (use_PBGC_CK_TIMESTEP ) then
      if (mnproc.eq.1) then
        write(io_stdo_bgc,*)' '
        write(io_stdo_bgc,*)'after ATMOTR: call INVENTORY'
      endif
      call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
    endif

    if (use_pref_tracers) then
      ! update preformed tracers
      call preftrc(kpie,kpje,omask)
    endif

    if (use_shelfsea_res_time) then
      ! Update shelf sea residence time tracer
      call shelfsea_residence_time(kpie,kpje,kpke,pddpo,shelfmask,omask)
    endif

    !--------------------------------------------------------------------
    !     Sediment module

    if (.not. use_sedbypass) then

      ! jump over sediment if sedbypass is defined

      if(do_sedspinup .and. kplyear>=sedspin_yr_s .and. kplyear<=sedspin_yr_e) then
        nspin = sedspin_ncyc
        if(mnproc == 1) then
          write(io_stdo_bgc,*)
          write(io_stdo_bgc,*) 'iHAMOCC: sediment spinup activated with ',nspin, ' subcycles'
        endif
      else
        nspin = 1
      endif

      ! Loop for sediment spinup. If deactivated then nspin=1 and lspin=.false.
      do it=1,nspin

        if( it<nspin ) then
          lspin=.true.
        else
          lspin=.false.
        endif

        call powach(kpie,kpje,kpke,kbnd,prho,omask,psao,ptho,lspin)

      enddo

      if (use_PBGC_CK_TIMESTEP ) then
        if (mnproc.eq.1) then
          write(io_stdo_bgc,*)' '
          write(io_stdo_bgc,*)'after POWACH: call INVENTORY'
        endif
        call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
      endif

      ! Sediment is shifted once a day (on both time levels!)
      ! sedshi relies on the choice that it is only called once per day
      if (KLDTDAY == 1 .OR. KLDTDAY == 2) then
        if (mnproc.eq.1) then
          write(io_stdo_bgc,*)' '
          write(io_stdo_bgc,*) 'Sediment shifting ...'
        endif
        call sedshi(kpie,kpje,omask,kplyear)
      endif

    endif ! .not. use_sedbypass

    if (use_PBGC_CK_TIMESTEP ) then
      if (mnproc.eq.1) then
        write(io_stdo_bgc,*)' '
        write(io_stdo_bgc,*)'after BGC: call INVENTORY'
      endif
      call inventory_bgc(kpie,kpje,kpke,pdlxp,pdlyp,pddpo,omask,0)
    endif

    !--------------------------------------------------------------------
    ! Pass co2 flux. Convert unit from kmol/m^2 to kg/m^2/s.

    !$OMP PARALLEL DO PRIVATE(i)
    do  j=1,kpje
      do  i=1,kpie
        if(omask(i,j) .gt. 0.5_rp) pflxco2(i,j)=-44._rp*atmflx(i,j,iatmco2)/dtbgc
      enddo
    enddo
    !$OMP END PARALLEL DO

    !--------------------------------------------------------------------
    ! Pass dms flux. Convert unit from kmol/m^2 to kg/m^2/s.

    !$OMP PARALLEL DO PRIVATE(i)
    do  j=1,kpje
      do  i=1,kpie
        if(omask(i,j) .gt. 0.5_rp) pflxdms(i,j)=-62.13_rp*atmflx(i,j,iatmdms)/dtbgc
      enddo
    enddo
    !$OMP END PARALLEL DO

    !--------------------------------------------------------------------
    ! Pass bromoform flux. Convert unit from kmol CHBr3/m^2 to kg/m^2/s.
    ! Negative values to the atmosphere

    !$OMP PARALLEL DO PRIVATE(i)
    do  j=1,kpje
      do  i=1,kpie
        if (use_BROMO) then
          if(omask(i,j) .gt. 0.5_rp) pflxbromo(i,j)=-252.7_rp*atmflx(i,j,iatmbromo)/dtbgc
        else
          if(omask(i,j) .gt. 0.5_rp) pflxbromo(i,j)=0.0_rp
        endif
      enddo
    enddo
    !$OMP END PARALLEL DO
    !--------------------------------------------------------------------
    ! Pass nitrous oxide and ammonia fluxes. Convert unit from kmol N2O (NH3)/m2/Delta t to kg/m2/s
    ! negative values to the atmosphere
    !$OMP PARALLEL DO PRIVATE(i)
    do  j=1,kpje
      do  i=1,kpie
        if (use_extNcycle) then
          if (do_n2o_coupled) then
              if(omask(i,j) > 0.5_rp) pflxn2o(i,j)=-mw_n2o*atmflx(i,j,iatmn2o)/dtbgc  ! conversion factor checked against CAM
          else
              if(omask(i,j) > 0.5_rp) pflxn2o(i,j)=0.0_rp
          endif
          if (do_nh3_coupled) then
              if(omask(i,j) > 0.5_rp) pflxnh3(i,j)=-mw_nh3*atmflx(i,j,iatmnh3)/dtbgc  ! conversion factor checked against CAM
          else
              if(omask(i,j) > 0.5_rp) pflxnh3(i,j)=0.0_rp
          endif
        else
          if(omask(i,j) > 0.5_rp) pflxn2o(i,j)=0.0_rp
          if(omask(i,j) > 0.5_rp) pflxnh3(i,j)=0.0_rp
        endif
      enddo
    enddo
    !$OMP END PARALLEL DO
    !--------------------------------------------------------------------
  end subroutine hamocc4bcm

end module mo_hamocc4bcm
