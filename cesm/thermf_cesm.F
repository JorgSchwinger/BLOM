! ------------------------------------------------------------------------------
! Copyright (C) 2008-2023 Mats Bentsen, Mehmet Ilicak
!
! This file is part of BLOM.
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
! along with BLOM. If not, see <https://www.gnu.org/licenses/>.
! ------------------------------------------------------------------------------

      subroutine thermf_cesm(m,n,mm,nn,k1m,k1n)
c
c --- NERSC version of thermf. To be used when coupled to CESM
c
      use mod_constants, only: g, spcifh, t0deg, alpha0, epsilt, onem,
     .                         g2kg, kg2g, L_mks2cgs, M_mks2cgs
      use mod_time, only: nstep, nstep_in_day, nday_in_year,
     .                    nday_of_year, baclin,
     .                    xmi, l1mi, l2mi, l3mi, l4mi, l5mi
      use mod_xc
      use mod_vcoord, only: vcoord_type_tag, isopyc_bulkml
      use mod_grid, only: scp2, area
      use mod_state, only: dp, temp, saln, p
      use mod_swtfrz, only: swtfrz
      use mod_forcing, only: sref, tflxap, sflxap, tflxdi, sflxdi,
     .                       nflxdi, aptflx, apsflx, ditflx, disflx,
     .                       sstclm, ricclm, sssclm, trxday, srxday,
     .                       trxdpt, srxdpt, trxlim, srxlim, srxbal,
     .                       swa, nsf, hmltfz, lip, sop, eva, rnf, rfi,
     .                       fmltfz, sfl, ustarw, surflx, surrlx,
     .                       sswflx, salflx, brnflx, salrlx, ustar,
     .                       t_rs_nonloc, s_rs_nonloc,
     .                       sss_stream, sst_stream, ice_stream,
     .                       use_stream_relaxation
      use mod_cesm, only: hmlt, frzpot, mltpot
      use mod_utility, only: util1, util2, util3, util4
      use mod_checksum, only: csdiag, chksummsk
#ifdef TRC
#  ifdef TKE
      use mod_tracers, only: ntr, itrtke, itrgls, trc, trflx
#    ifdef GLS
      use mod_diffusion, only: difdia
      use mod_tke, only: gls_cmu0, Zos, gls_p, gls_m, gls_n, vonKar
#    endif
#  else
      use mod_tracers, only: ntr, trc, trflx
#  endif
#endif
c
      implicit none
c
      integer m,n,mm,nn,k1m,k1n
c
      real, dimension(1-nbdy:idm+nbdy,1-nbdy:jdm+nbdy) ::
     .  tfrz,tfrzm,vrtsfl
c
      integer i,j,k,l,m1,m2,m3,m4,m5,ntld,kn,kl
      real y,dpotl,hotl,totl,sotl,tice_f,fwflx,sstc,rice,dpmxl,hmxl,
     .     tmxl,trxflx,pbot,dprsi,sssc,smxl,srxflx,totsfl,totwfl,sflxc,
     .     totsrp,totsrn,qp,qn,A_cgs2mks
#ifdef TRC
      integer nt
      real, dimension(ntr,1-nbdy:idm+nbdy,1-nbdy:jdm+nbdy) ::
     .  ttrsf,ttrav
      real tottrsf,tottrav,trflxc
#endif
c
      real intp1d
      external intp1d
c
      A_cgs2mks=1./(L_mks2cgs**2)
c
c --- Set parameters for time interpolation when applying diagnosed heat
c --- and salt relaxation fluxes
      y=(nday_of_year-1+mod(nstep,nstep_in_day)/real(nstep_in_day))*48.
     .  /real(nday_in_year)
      m3=int(y)+1
      y=y-real(m3-1)
      m1=mod(m3+45,48)+1
      m2=mod(m3+46,48)+1
      m4=mod(m3   ,48)+1
      m5=mod(m3+ 1,48)+1
c
c --- Time level for diagnosing heat and salt relaxation fluxes
      ntld=m3
c
c --- Compute freezing temperatures of sea water
      tfrz(:,:)=swtfrz(p(:,:,1),saln(:,:,k1n))
      tfrzm(:,:)=swtfrz(p(:,:,1),.5*(saln(:,:,k1m)+saln(:,:,k1n)))
c
      if (ditflx.or.disflx) nflxdi(ntld)=nflxdi(ntld)+1
c
c$OMP PARALLEL DO PRIVATE(
c$OMP+ l,i,dpotl,hotl,totl,sotl,tice_f,fwflx,sstc,rice,dpmxl,hmxl,tmxl,
c$OMP+ trxflx,pbot,dprsi,kn,kl,sssc,smxl,srxflx
#ifdef TRC
c$OMP+ ,nt
#endif
c$OMP+ )
      do j=1,jj
        do l=1,isp(j)
        do i=max(1,ifp(j,l)),min(ii,ilp(j,l))
c
c --- ------------------------------------------------------------------
c --- --- Set some quantities
c --- ------------------------------------------------------------------
c
c --- --- ocean top layer quantities
          dpotl=dp(i,j,k1n)
          hotl=dpotl/onem
          totl=temp(i,j,k1n)+t0deg
          sotl=saln(i,j,k1n)
c
          tice_f=tfrz(i,j)+t0deg
c
c --- ------------------------------------------------------------------
c --- --- Fresh water and salt fluxes
c --- ------------------------------------------------------------------
c
c --- --- Fresh water flux [kg m-2 s-1] (positive downwards)
          fwflx=eva(i,j)+lip(i,j)+sop(i,j)+rnf(i,j)+rfi(i,j)+fmltfz(i,j)
c
c --- --- Salt flux due to brine rejection of freezing sea
c --- --- ice [kg m-2 m-1] (positive downwards)
          brnflx(i,j)=max(0.,-sotl*fmltfz(i,j)*g2kg+sfl(i,j))
c
c --- --- Virtual salt flux [kg m-2 s-1] (positive downwards)
          vrtsfl(i,j)=-sotl*fwflx*g2kg
c
c --- --- Store area weighted virtual salt flux and fresh water flux
          util1(i,j)=vrtsfl(i,j)*scp2(i,j)
          util2(i,j)=fwflx*scp2(i,j)
c
c --- ------------------------------------------------------------------
c --- --- Heat fluxes
c --- ------------------------------------------------------------------
c
c --- --- Freezing/melting potential [J m-2]. A positive flux means the ocean
c --- --- surface has a temperature below freezing temperature and must
c --- --- be heated. Note the freezing potential is multiplied by 1/2
c --- --- due to the leap-frog time stepping. The melting potential uses
c --- --- time averaged quantities since it is not accumulated.
          frzpot(i,j)=max(0.,tice_f-totl)*spcifh*dpotl
     .                /(2.*g)*(L_mks2cgs**2)
          mltpot(i,j)=
     .      min(0.,tfrzm(i,j)-.5*(temp(i,j,k1m)+temp(i,j,k1n)))
     .      *spcifh*.5*(dp(i,j,k1m)+dp(i,j,k1n))/g*(L_mks2cgs**2)
c
c --- --- Heat flux due to melting/freezing [W m-2] (positive downwards)
          hmltfz(i,j)=hmlt(i,j)+frzpot(i,j)/baclin
c
c --- --- Total heat flux in BLOM units [W cm-2] (positive upwards)
          surflx(i,j)=-(swa(i,j)+nsf(i,j)+hmltfz(i,j))*A_cgs2mks
c
c --- --- Short-wave heat flux in BLOM units [W cm-2] (positive
c --- --- upwards)
          sswflx(i,j)=-swa(i,j)*A_cgs2mks
c
#ifdef TRC
c --- ------------------------------------------------------------------
c --- --- Tracer fluxes (positive downwards)
c --- ------------------------------------------------------------------
c
          do nt=1,ntr
#  ifdef TKE
            if (nt.eq.itrtke) then
              trflx(nt,i,j)=0.
              ttrsf(nt,i,j)=0.
              ttrav(nt,i,j)=0.
              cycle
            endif
#    ifdef GLS
            if (nt.eq.itrgls) then
              trflx(nt,i,j)=-gls_n*difdia(i,j,1)*(gls_cmu0**gls_p)
     .                       *(trc(i,j,k1n,itrtke)**gls_m)
     .                       *(vonKar**gls_n)*Zos**(gls_n-1.)
              ttrsf(nt,i,j)=0.
              ttrav(nt,i,j)=0.
              cycle
            endif
#    else
            if (nt.eq.itrgls) then
              trflx(nt,i,j)=0.
              ttrsf(nt,i,j)=0.
              ttrav(nt,i,j)=0.
              cycle
            endif
#    endif
#  endif
            trflx(nt,i,j)=-trc(i,j,k1n,nt)*fwflx
            ttrsf(nt,i,j)=trflx(nt,i,j)*scp2(i,j)
            ttrav(nt,i,j)=trc(i,j,k1n,nt)*scp2(i,j)
          enddo
#endif
c
c --- ------------------------------------------------------------------
c --- --- Relaxation fluxes
c --- ------------------------------------------------------------------
c
          surrlx(i,j)=0.
c
c --- --- If  trxday>0 , apply relaxation towards observed sst
          if (trxday > epsilt ) then

            if (use_stream_relaxation) then
              sstc = sst_stream(i,j)
              rice = ice_stream(i,j)
              sstc = (1.-rice)*max(sstc,tice_f) + rice*tice_f
            else
              sstc=intp1d(sstclm(i,j,l1mi),sstclm(i,j,l2mi),
     .                    sstclm(i,j,l3mi),sstclm(i,j,l4mi),
     .                    sstclm(i,j,l5mi),xmi)
              rice=intp1d(ricclm(i,j,l1mi),ricclm(i,j,l2mi),
     .                    ricclm(i,j,l3mi),ricclm(i,j,l4mi),
     .                    ricclm(i,j,l5mi),xmi)
              sstc=(1.-rice)*max(sstc,tice_f)+rice*tice_f
            end if

            if (vcoord_type_tag == isopyc_bulkml) then
              dpmxl=dp(i,j,1+nn)+dp(i,j,2+nn)
              hmxl=dpmxl/onem
              tmxl=(temp(i,j,1+nn)*dp(i,j,1+nn)
     .             +temp(i,j,2+nn)*dp(i,j,2+nn))/dpmxl+t0deg
              trxflx=spcifh*L_mks2cgs*min(hmxl,trxdpt)/(trxday*86400.)
     .               *min(trxlim,max(-trxlim,sstc-tmxl))/alpha0
            else
              pbot=p(i,j,1)
              do k=1,kk
                kn=k+nn
                pbot=pbot+dp(i,j,kn)
              enddo
              dprsi=1./min(trxdpt*onem,pbot-p(i,j,1))
              t_rs_nonloc(i,j,1)=1.
              tmxl=0.
              do k=1,kk
                kn=k+nn
                t_rs_nonloc(i,j,k+1)=t_rs_nonloc(i,j,k)-dp(i,j,kn)*dprsi
                if (t_rs_nonloc(i,j,k+1).lt.0.) then
                  tmxl=tmxl+temp(i,j,kn)*t_rs_nonloc(i,j,k)+t0deg
                  exit
                else
                  tmxl=tmxl+temp(i,j,kn)*(t_rs_nonloc(i,j,k  )
     .                                   -t_rs_nonloc(i,j,k+1))
                endif
              enddo
              do kl=k,kk
                t_rs_nonloc(i,j,kl+1)=0.
              enddo
              trxflx=spcifh*L_mks2cgs*trxdpt/(trxday*86400.)
     .               *min(trxlim,max(-trxlim,sstc-tmxl))/alpha0
            endif
            surrlx(i,j)=-trxflx
          else
            trxflx=0.
          endif
c
c --- --- If aptflx=.true., apply diagnosed relaxation flux
          if (aptflx) then
            surrlx(i,j)=surrlx(i,j)
     .        -intp1d(tflxap(i,j,m1),tflxap(i,j,m2),tflxap(i,j,m3),
     .                tflxap(i,j,m4),tflxap(i,j,m5),y)
          endif
c
c --- --- If ditflx=.true., diagnose relaxation flux by accumulating the
c --- --- relaxation flux
          if (ditflx) then
            tflxdi(i,j,ntld)=tflxdi(i,j,ntld)+trxflx
          endif
c
          salrlx(i,j)=0.
c
c --- --- if  srxday>0 , apply relaxation towards observed sss
          if (srxday > epsilt ) then
            if (use_stream_relaxation) then
              sssc = sss_stream(i,j)
            else
              sssc=intp1d(sssclm(i,j,l1mi),sssclm(i,j,l2mi),
     .                    sssclm(i,j,l3mi),sssclm(i,j,l4mi),
     .                    sssclm(i,j,l5mi),xmi)
            end if
            if (vcoord_type_tag == isopyc_bulkml) then
              dpmxl=dp(i,j,1+nn)+dp(i,j,2+nn)
              hmxl=dpmxl/onem
              smxl=(saln(i,j,1+nn)*dp(i,j,1+nn)
     .             +saln(i,j,2+nn)*dp(i,j,2+nn))/dpmxl
              srxflx=L_mks2cgs*min(hmxl,srxdpt)/(srxday*86400.)
     .               *min(srxlim,max(-srxlim,sssc-smxl))/alpha0
            else
              pbot=p(i,j,1)
              do k=1,kk
                kn=k+nn
                pbot=pbot+dp(i,j,kn)
              enddo
              dprsi=1./min(srxdpt*onem,pbot-p(i,j,1))
              s_rs_nonloc(i,j,1)=1.
              smxl=0.
              do k=1,kk
                kn=k+nn
                s_rs_nonloc(i,j,k+1)=s_rs_nonloc(i,j,k)-dp(i,j,kn)*dprsi
                if (s_rs_nonloc(i,j,k+1).lt.0.) then
                  smxl=smxl+saln(i,j,kn)*s_rs_nonloc(i,j,k)
                  exit
                else
                  smxl=smxl+saln(i,j,kn)*(s_rs_nonloc(i,j,k  )
     .                                   -s_rs_nonloc(i,j,k+1))
                endif
              enddo
              do kl=k,kk
                s_rs_nonloc(i,j,kl+1)=0.
              enddo
              srxflx=L_mks2cgs*srxdpt/(srxday*86400.)
     .               *min(srxlim,max(-srxlim,sssc-smxl))/alpha0
            endif
            salrlx(i,j)=-srxflx
            util3(i,j)=max(0.,salrlx(i,j))*scp2(i,j)
            util4(i,j)=min(0.,salrlx(i,j))*scp2(i,j)
          else
            srxflx=0.
          endif
c
c --- --- If apsflx=.true., apply diagnosed relaxation flux
          if (apsflx) then
            salrlx(i,j)=salrlx(i,j)
     .        -intp1d(sflxap(i,j,m1),sflxap(i,j,m2),sflxap(i,j,m3),
     .                sflxap(i,j,m4),sflxap(i,j,m5),y)
          endif
c
c --- --- If disflx=.true., diagnose relaxation flux by accumulating the
c --- --- relaxation flux
          if (disflx) then
            sflxdi(i,j,ntld)=sflxdi(i,j,ntld)+srxflx
          endif
c
c --- -------------------------------------------------------------------
c --- --- Friction velocity (cm/s)
c --- -------------------------------------------------------------------
c
          ustar(i,j)=ustarw(i,j)*L_mks2cgs
c
        enddo
        enddo
      enddo
c$OMP END PARALLEL DO
c
c --- ------------------------------------------------------------------
c --- Compute correction to the virtual salt flux so it is globally
c --- consistent with a salt flux based on some reference salinity.
c --- Also combine virtual and true salt flux and convert salt fluxes
c --- used later to unit [10e-3 g cm-2 s-1] and positive upwards.
c --- ------------------------------------------------------------------
c
      call xcsum(totsfl,util1,ips)
      call xcsum(totwfl,util2,ips)
c
c --- Correction for the virtual salt flux [kg m-2 s-1]
      sflxc=(-sref*totwfl*g2kg-totsfl)/area
      if (mnproc.eq.1) then
        write (lp,*) 'thermf: totsfl/area,sflxc',totsfl/area,sflxc
      endif
c
c --- Apply the virtual salt flux correction and the compute the total
c --- salt flux by combining the virtual and true salt flux
c$OMP PARALLEL DO PRIVATE(l,i)
      do j=1,jj
        do l=1,isp(j)
        do i=max(1,ifp(j,l)),min(ii,ilp(j,l))
          salflx(i,j)=-(vrtsfl(i,j)+sflxc+sfl(i,j))
     .                 *(kg2g*(M_mks2cgs/L_mks2cgs**2))
          brnflx(i,j)=-brnflx(i,j)
     .                 *(kg2g*(M_mks2cgs/L_mks2cgs**2))
        enddo
        enddo
      enddo
c$OMP END PARALLEL DO
c
c --- if  srxday>0  and  srxbal=.true. , balance the sss relaxation flux
c --- so the net input of salt in grid cells connected to the world
c --- ocean is zero
      if (srxday.gt.epsilt.and.srxbal) then
        call xcsum(totsrp,util3,ipwocn)
        call xcsum(totsrn,util4,ipwocn)
        if (abs(totsrp-totsrn).gt.0.) then
          qp=2.*totsrn/(totsrn-totsrp)
          qn=2.*totsrp/(totsrp-totsrn)
c$OMP PARALLEL DO PRIVATE(l,i)
          do j=1,jj
            do l=1,isp(j)
            do i=max(1,ifp(j,l)),min(ii,ilp(j,l))
              if (ipwocn(i,j).eq.1) then
                salrlx(i,j)=qp*max(0.,salrlx(i,j))
     .                     +qn*min(0.,salrlx(i,j))
              endif
            enddo
            enddo
          enddo
c$OMP END PARALLEL DO
        endif
      endif
c
#ifdef TRC
      do nt=1,ntr
c
#  ifdef TKE
        if (nt.eq.itrtke.or.nt.eq.itrgls) cycle
#  endif
c$OMP PARALLEL DO PRIVATE(l,i)
        do j=1,jj
          do l=1,isp(j)
          do i=max(1,ifp(j,l)),min(ii,ilp(j,l))
            util1(i,j)=ttrsf(nt,i,j)
            util2(i,j)=ttrav(nt,i,j)
          enddo
          enddo
        enddo
c$OMP END PARALLEL DO
c
        call xcsum(tottrsf,util1,ips)
        call xcsum(tottrav,util2,ips)
c
        tottrav=tottrav/area
c
        trflxc=(-tottrsf)/area
c        trflxc=(-tottrav*totwfl*g2kg-tottrsf)/area
c        trflxc=0.
c
c$OMP PARALLEL DO PRIVATE(l,i)
        do j=1,jj
          do l=1,isp(j)
          do i=max(1,ifp(j,l)),min(ii,ilp(j,l))
            trflx(nt,i,j)=-(trflx(nt,i,j)+trflxc)
     .                     *(M_mks2cgs/L_mks2cgs**2)
          enddo
          enddo
        enddo
c$OMP END PARALLEL DO
c
      enddo
#endif
c
      if (csdiag) then
        if (mnproc.eq.1) then
          write (lp,*) 'thermf_cesm:'
        endif
        call chksummsk(surflx,ip,1,'surflx')
        call chksummsk(sswflx,ip,1,'sswflx')
        call chksummsk(salflx,ip,1,'salflx')
        call chksummsk(brnflx,ip,1,'brnflx')
        call chksummsk(surrlx,ip,1,'surrlx')
        call chksummsk(salrlx,ip,1,'salrlx')
        call chksummsk(hmltfz,ip,1,'hmltfz')
        call chksummsk(ustar,ip,1,'ustar')
        call chksummsk(frzpot,ip,1,'frzpot')
        call chksummsk(mltpot,ip,1,'mltpot')
        if (vcoord_type_tag /= isopyc_bulkml) then
          call chksummsk(t_rs_nonloc, ip, kk+1, 't_rs_nonloc')
          call chksummsk(s_rs_nonloc, ip, kk+1, 's_rs_nonloc')
        endif
      endif
c
      return
      end
