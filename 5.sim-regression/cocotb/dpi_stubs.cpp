extern "C" {
void VInit(unsigned int n) {}
void VSched(unsigned int n, unsigned int t, unsigned int *a, unsigned int *b, unsigned int *c, unsigned int *d) {}
void VAccess(unsigned int n, unsigned int a, unsigned int b, unsigned int *c) {}
void VIrq(unsigned int n, unsigned int a) {}
void MemModelRead(unsigned int a, unsigned int *b, unsigned int c) {}
void MemModelWrite(unsigned int a, unsigned int b, unsigned int c) {}
}
