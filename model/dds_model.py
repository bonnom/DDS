from fixedpoint import FixedPoint
from bitstring import BitArray

import math
import numpy as np

class Model:
    def __init__(self, PHASE_DW, OUT_DW, USE_TAYLOR, LUT_DW):
        self.PHASE_DW = PHASE_DW
        self.OUT_DW = OUT_DW
        self.USE_TAYLOR = USE_TAYLOR
        self.LUT_DW = LUT_DW
        
        self.extra_delay = 5                
        self.data_out_buf = np.zeros(self.extra_delay+1)
        self.out_valid = np.zeros(self.extra_delay+1)
        self.in_valid = 0
        self.data_in_buf = 0


    def set_data(self, data_in):
        self.data_in_buf = data_in
        self.in_valid = 1
        
    def reset(self):
        self.data_out_buf = np.zeros(self.extra_delay+1)
        self.out_valid = np.zeros(self.extra_delay+1)
        self.in_valid = 0
        self.data_in_buf = 0

    def data_valid(self):
        return self.out_valid[self.extra_delay]

    def get_data(self):
        return self.data_out_buf[self.extra_delay]
        
    def tick(self):

        if self.in_valid == 1:
            self.out_valid[0] = 1
            self.in_valid = 0
        
        data_in_max = 2**self.PHASE_DW
        self.data_out_buf[0] = np.round(np.sin(self.data_in_buf*2*np.pi/data_in_max) * (2**(self.OUT_DW-1)-1))
        #if self.out_valid[0]:
        #    print(F"sin({self.data_in_buf*2*np.pi/data_in_max}) = {np.sin(self.data_in_buf*2*np.pi/data_in_max)* (2**(self.OUT_DW-1)-1)}")
        for i in np.arange(self.extra_delay-1,-1,-1):
            self.data_out_buf[i+1] = self.data_out_buf[i]
            self.out_valid[i+1] = self.out_valid[i] 
            
            
    
