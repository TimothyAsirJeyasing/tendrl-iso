
ARGS = --config=build.cfg
ARGS += --kickstart=rhscon.ks

scratch: 
	brew image-build $(ARGS) --scratch

image: 
	brew image-build $(ARGS)
