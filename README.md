# Ember Tide

*A shoreline that remembers being touched.*


https://github.com/user-attachments/assets/19421a6d-06c5-4458-aa1f-6e120ee42b0a


Ember Tide is a personal project I built on my own in Unity. The idea was to emulate a bioluminescent shoreline at night: waves coming in out of the dark, breaking, running up the sand and draining back, with the glow coming from the water being disturbed rather than from light painted onto the wave.

I wanted the light to behave the way dinoflagellate plankton actually do on a real beach, firing where the water is sheared, lingering briefly on the wet sand, and fading as things settle, and I wanted every wave to be its own event so the scene never repeats. The surf, the foam and the particles are all simulated on the GPU in real time, and anyone can disturb the water, which moves it rather than adding light, so the glow that follows is the sea responding to the touch.

It is framed top-down so it can be projected onto a floor, and it is built to take input from motion sensing hardware such as a Hokuyo LiDAR scanner or an Azure Kinect or Orbbec Femto depth camera, so that footsteps on the projected surface are read as disturbances in the water in the same way a pointer is on a desktop.

## Research

Papers I read while working on the foam and on where the light should come from:

- Mary Yingst, Jennifer R. Alford, Ian Parberry. *Very Fast Real-Time Ocean Wave Foam Rendering Using Halftoning.* University of North Texas, 2011. [PDF](https://ianparberry.com/techreports/LARC-2011-05.pdf)
- M. D. Stokes, G. B. Deane, M. I. Latz, J. Rohr. *Bioluminescence imaging of wave-induced turbulence.* Journal of Geophysical Research: Oceans, 2004. [doi](https://doi.org/10.1029/2003JC001871)
- Hao et al. *Quantifying Bioluminescent Light Intensity in Breaking Waves Using Numerical Simulations.* Geophysical Research Letters, 2024. [doi](https://doi.org/10.1029/2024GL110884)
- M. Jalaal et al. *Stress-Induced Dinoflagellate Bioluminescence at the Single Cell Level.* Physical Review Letters, 2020. [PDF](https://www.damtp.cam.ac.uk/user/gold/pdfs/bioluminescence.pdf)
