      program Fract_Haz45

c     This program will compute the fractiles from a seismic hazard
c     run. This version of the program works with the seismic hazard
c     code version 43 or later. The fractiles are computed based on 
c     a Monte Carlo simulation. This version will be able to read fault
c     files in which synchronous rupture is modeled. 
 
c     compatible with Haz45
c     Last modified: 2/11

      implicit none
      include 'fract.h'
      
      integer iPer, nFlt0, nattentype, nProb, iFlt0, iFlt1, jAttenType, jFlt,
     1        i, j, k, jj, i1, i2, j2, nn100, iSample, mcSegModel, mcFType, 
     2        mcWidth, mcParam, nperc, nInten, nAtten(MAX_FLT), nsite, nFlt,
     3        isite, iflt, iInten, nWidth(MAX_FLT), nParamVar(MAX_FLT,MAX_WIDTH),
     4        iX(MAX_FILES), attentype(MAX_FLT), nGM_model(MAX_ATTENTYPE)
      integer iperc, nfiles, iseed, nSample, nFtype(MAX_FLT), mcatten(MAX_SAMPLE),
     1        f_start(MAX_FLT), f_num(MAX_FLT), nSegModel(MAX_FLT), iAmp,
     2        faultflag(MAX_FLT,MAX_SEG,MAX_FLT), iWidth, iFract
      real tempx, step, risk(MAX_INTEN,MAX_ATTEN,MAX_FLT,MAX_WIDTH,MAXPARAM,MAX_FTYPE), 
     1     testInten(MAX_INTEN), al_segwt(MAX_FLT), probAct(MAX_FLT), 
     2     cumWt_segModel(MAX_FLT,MAX_SEG), cumWt_param(MAX_FLT,MAX_WIDTH,MAXPARAM),
     3     cumWt_Width(MAX_FLT,MAX_WIDTH), cumWt_Ftype(MAX_FLT,MAX_FTYPE),
     4     ran1, risk1(MAX_SAMPLE,MAX_INTEN), sortarray(MAX_SAMPLE)
      real cumWt_GM(MAX_ATTEN,MAX_ATTEN), perc(100,MAX_INTEN),mean(MAX_INTEN),
     1     hazTotal(100), UHS(3), specT1, specT, hazLevel, x, testHaz 
      character*80 filein, file1    

*** need to fix: treating all ftype as epistemic
        
      write (*,*) '*************************'
      write (*,*) '*   Fractile Code for   *'
      write (*,*) '*       HAZ45-v2        *'
      write (*,*) '*    July 2016, NAA     *'
      write (*,*) '*************************'

      write (*,*) 'Enter the input filename.'
      
      read (*,'(a80)') filein
      open (31,file=filein,status='old')

      read (31,*) iseed
      read (31,*) nSample
      read (31,*) iPer

      call CheckDim ( nSample, MAX_SAMPLE, 'MAX_SAMPLE ' )

c     Read Input File
      call RdInput ( nFlt, nFlt0, f_start, f_num, faultFlag, nInten, 
     1     testInten, probAct, al_segWt, cumWt_SegModel, cumWt_Width, 
     2     cumWt_param, cumWt_ftype, cumWt_GM, nSegModel, nWidth, 
     3     nParamVar, nFtype, nGM_model, nattentype, attenType, 
     4     nProb, iPer, specT1)
     
c     Write out weights as a check
      do iFlt=1,nFlt
        write (*,'( 2x,''GM wts'')')
        do i=1,nattentype
          write (*,'( 10f10.3)') (cumWt_GM(i,k),k=1,nGM_model(i))
        enddo
      enddo

      do iFlt0=1,nFlt0
        write (*,'( 2x,''SegModel wts for system:'', i5)') iFlt0
        write (*,'( 10f10.3)') (cumWt_segModel(iFlt0,k),k=1,nSegModel(iFlt0))
      enddo
      
      do iFLt=1,nFlt
        write (*,'( 2x,''width wts for fault:'', i5)') iFlt
        write (*,'( 10f10.3)') (cumWt_Width(iFlt,k),k=1,nWidth(iFlt) )
      
        write (*,'( 2x,''param wts for fault'', i5)') iFlt
        do iWidth=1,nWidth(iFlt)
          write (*,'( 2x,''iWidth:'',i5)') iWidth
          write (*,'( 10f10.3)') (cumWt_param(iFlt,iWidth,k),k=1,nParamVar(iflt,iWidth))
        enddo      
      enddo
      pause 'end of test wts'     
        
c     Loop Over Number of Sites
      nsite = 1
      do 1000 iSite = 1, nSite

c       Initialize risk1 and mean
        do i=1,nSample
          do j=1,MAX_INTEN
            risk1(i,j) = 0.
          enddo
        enddo

c       Initialize mean
        do i=1,MAX_INTEN
          mean(i) = 0.
        enddo

c       Initialize random number generator
        do i=1,500
          tempx = Ran1 (iseed)
        enddo
       
        write (*,'( 2x,''reading logictree file'')')
        call read_logicRisk ( isite, nSite, nFlt, nfiles, ix, risk, 
     1       nParamVar, natten, nFtype, iPer, nProb )

       write (*,'( 2x,''out of logicrisk'')')

c       Monte Carlo Sampling of Hazard
        do iSample=1,nSample

          nn100 = (iSample/100)*100
          if ( nn100 .eq. iSample) then
             write (*,*) 'Looping over samples:        ', iSample, ' of ', nSample
          endif

c         Sample the attenuation relation (correlated for all sources)
          do jj=1,nAttenType
           call GetRandom1 ( iseed, nGM_model(jj), cumWt_GM, jj, mcAtten(jj), MAX_ATTEN, 1 ) 
          enddo
              
c         Sample the hazard from each geometrically independent source region (or fault)
c         (a source region may include multiple subsources) 
          do iFlt0 = 1, nFlt0

c           Select the seg model for this source region
            call GetRandom1 ( iseed, nSegModel(iFlt0), cumWt_segModel, iflt0, mcSegModel, MAX_FLT, 2 )

            i1 = f_start(iFlt0)
            i2 = f_start(iFlt0) + f_num(iFLt0) - 1

            do iflt1=i1,i2

c             set the attenuation type for this fault
              jAttenType = attenType(iflt1)

c             Reset the index to the faults in segment
              jFlt = iFlt1-i1+1

c             Skip this fault if not included in this seg model
              if (faultflag(iFlt0,mcSegModel,jFlt) .eq. 0. ) goto 50

c *** fix this ***
c              write (*,'( i5)') nFtype(iFlt1)
c              write (*,'( 10f10.4)') (cumWt_Ftype(iflt1, ii),ii=1,nFtype(iFLt1) )
c             Select the fault mechanism type 
c              call GetRandom1b ( iseed, nFtype(iFlt1), cumWt_Ftype, iflt1, mcFTYPE, MAX_FTYPE, MAX_FLT )
c   * not working, all set to 1 for now.
               mcFType = 1

c             Select the fault width for this subsource 
              call GetRandom1 ( iseed, nWidth(iFlt1), cumWt_width, iflt1, mcWidth, MAX_FLT, 3 )

c             Select the parameter variation for this subsource and fault width
              call GetRandom2 (iseed, nParamVar(iFlt1,mcWidth), 
     1          cumWt_param, iFlt1, mcWidth, mcParam, MAX_FLT, MAX_WIDTH)

c             Add the sampled hazard curve to the total hazard
              do iInten=1,nInten
                risk1(iSample,iInten) = risk1(iSample,iInten) 
     1                    + risk(iInten,mcAtten(jAttenType),iFlt1,mcWidth,mcParam,mcFtype)
     1                    * al_segwt(iflt1)
                mean(iInten)=mean(iInten)
     1	 	          + risk(iInten,mcAtten(jAttenType),iFlt1,mcWidth,mcParam,mcFtype)
     1                    * al_segwt(iflt1)
              enddo
  50          continue

c           end loop over faults in this flt system
            enddo

c         end loop over flt systems
          enddo

c       end loop over number of monte carlo samples
        enddo

c       Compute mean hazard as check between fractile and haz code
         do iInten = 1,nInten
           mean(iInten) = mean(iInten)/nSample
        enddo

c       Sort risk data so that cummulative empirical distribution function
c       can be computed  (sorts in place)
c       sortarray is a working array
        do iInten = 1,nInten
           call sort(risk1(1,iInten),sortarray,nSample)
        enddo

        nperc = 99
c       Compute fractile values
        step = 1./(nperc+1)
        do iInten=1,nInten
          do iperc = 1,nPerc
            i1 = int(iperc*step*nSample)
  	    perc(iperc,iInten) = risk1(i1,iInten)
          enddo
	enddo

c       Write output
        read (31,'( a80)') file1
        write(*,'( a32,a80)') 'Writing results to output file: ',file1

        open (30,file=file1,status='new')
        write(30,'(3x,25f12.4)') (testInten(J2),J2=1,nInten)

        do i=1,nPerc
          write (30,'(2x,f4.2,30e12.4)') i*step, (perc(i,k),k=1,nInten)
        enddo

        write(30,'(/,2x,a4,30e12.4)') 'mean', (mean(j),j=1,nInten) 
 
c       Compute the UHS value for this period for the 5th, 50th, 95th
        hazLevel = 1.E-4
        do iFract=1,3
          if ( iFract .eq. 1 ) i1 = 5
          if ( iFract .eq. 2 ) i1 = 50          
          if ( iFract .eq. 3 ) i1 = 95
          
          do k=1,nInten
            hazTotal(k) = perc(i1,k)
          enddo
          
          testHaz = hazLevel
	  do iAmp=2,nInten

c          Check for zero values in hazard curve.
           if (hazTotal(iAmp) .eq. 0. ) then
            write (*,*) 'warning: Zero Values for hazard curve at desired haz level.'
            write (*,*) 'Setting UHS to last nonzero value'
            UHS(iFract) = exp(x)
           endif
          
c          Interpolate the hazard curve.
           if ( hazTotal(iAmp) .lt. testHaz ) then
            x = ( alog(testHaz) - alog(hazTotal(iAmp-1)) )/
     1            ( alog(hazTotal(iAmp))-alog(hazTotal(iAmp-1))) 
     2          * (alog(testInten(iAmp))-alog(testInten(iAmp-1))) 
     3          + alog(testInten(iAmp-1))
            UHS(iFract) = exp(x)
            goto 65
           endif
         enddo
 65     continue
      enddo
      write (30,'( f10.3,3e15.4)') specT, (UHS(k),k=1,3)

c       INterp goes here     
     
        close (30)

 1000 continue

      write (*,*) 
      write (*,*) '*** Fractile Code (45) Completed with Normal Termination ***'

      stop
      end

c -------------------------------------------------------------------

      subroutine read_logicRisk ( isite, nSite, nFlt, nfiles, ix, risk, 
     1           nParamVar, nAtten, nFtype, iPer, nProb)

      implicit none
      include 'fract.h'

      integer isite, nInten, nFlt,  nSite, nAtten(1),ix(MAX_FILES), iProb,
     1        nParamVar(MAX_FLT,MAX_WIDTH), nWidth(MAX_FLT), nfiles,
     2        nFtype(MAX_FLT), iPer, nProb, nwr, i, j, iFlt, jProb, jFlt, 
     3        i1, iAtten, iWidth, iFtype
      real risk(MAX_INTEN,MAX_ATTEN,MAX_FLT,MAX_WIDTH,MAXPARAM,MAX_FTYPE),
     1     temp(MAX_INTEN)
      character*80 file1

      nwr = 12
      nfiles = 1

C     Loop over the number of files.
      do 100 i1=1,nfiles
                     
c     Open output file
      read (31,'( a80)') file1

      write (*,*) 'Opening output file from the hazard runs.'
      write (*,*) file1
      open (nwr,file=file1,status='old')

C      Loop over nSite taken out since each site is now given its own output file
c           from the hazard code.
            
      do iFlt=1,nFlt      
        
        do jProb=1,nProb

         read (nwr,*) jFlt, iProb, nAtten(iFlt), nWidth(iFlt), nFtype(iFlt), 
     1         (nParamVar(iFlt,i),i=1,nWidth(iFlt)),
     2         nInten

C     Check for Array Dimension of Risk Array.
         if (nFlt .gt. MAX_FLT) then
           write (*,*) 'MAX_FLT needs to be increased to ', nFlt
           write (*,*) 'Change Array Parameter in FRACT.H and recompile.'
           stop 99
         endif
         if (nWidth(iFlt) .gt. MAX_WIDTH) then
           write (*,*) 'MAX_WIDTH needs to be increased to ', nWidth(iFlt)
           write (*,*) 'Change Array Parameter in FRACT.H and recompile.'
           stop 99
         endif
         if (iProb .gt. MAX_PROB) then
           write (*,*) 'MAX_PROB needs to be increased to ', iProb
           write (*,*) 'Change Array Parameter in FRACT.H and recompile.'
           stop 99
         endif
         if (nFtype(iFlt) .gt. MAX_FTYPE) then
           write (*,*) 'MAX_FTYPE needs to be increased to ', nFtype(iFlt)
           write (*,*) 'Change Array Parameter in FRACT.H and recompile.'
           stop 99
         endif

          do iAtten=1,nAtten(iFlt)
            do iWidth=1,nWidth(iFlt)
               do iFtype=1,nFtype(iFlt)
                  do i=1,nParamVar(iFlt,iWidth)
 	             read (nwr,*) (temp(j),j=1,nInten)

c                    Only keep if it is the desired spectral period
	             if ( iProb .eq. iPer) then
                       do j=1,nInten
	                 Risk(j,iAtten,iFlt,iWidth,i,iFtype) = temp(j)
	               enddo
                     endif
                  enddo
               enddo
	    enddo
          enddo
        enddo
      enddo

      close (nwr)

  100 continue

      return
  
      write (*,'( 2x,''bad site number'')')
      stop 98

      end

c -------------------------------------------------------------------------
