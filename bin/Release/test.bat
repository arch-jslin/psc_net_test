@setlocal
@set port_start=2000
@set port_range=10

@if "%1" neq "" @set port_start=%1
@if "%2" neq "" @set port_range=%2

@set /a port_end=%port_start%+%port_range%-1

@for /L %%G IN (%port_start%,1,%port_end%) DO start psc_net_test.exe %%G 
