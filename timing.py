"""Provides a python-based interface to timeit"""
from timeit import default_repeat, Timer
from enum import Enum


class OutType(str, Enum):
    """Output type enumerator"""
    STR = 'str'
    NUM = 'num'


class AutoTimerProperties(type):
    @property
    def units(cls):
        return cls._units
    
    @units.setter
    def units(cls, new_units):
        from numbers import Number
        new_units = list(new_units)
        for scale, unit in new_units:
            if not isinstance(scale, Number) or not str(unit):
                raise TypeError('incompatible units list')
        cls._units = [(scale, str(unit)) for scale, unit in new_units]


class AutoTimer(Timer, metaclass=AutoTimerProperties):
    """Auto-ranging Timer object"""
    _units = [(1.0, "sec"), (1e-3, "msec"), (1e-6, "usec"), (1e-9, "nsec")]
    
    def auto(self,
             repeat=default_repeat,
             callback=None,
             precision=3,
             outptype=OutType.STR):
        """Auto-range and time"""
        def format_time(time):
            from math import log10
            for scale, unit in self.units:
                if time >= scale:
                    break
            len_ = precision
            time = time / scale
            if int(log10(time))+1 < precision:
                len_ = precision + 1
            return '{:0<{len}.{prec}g} {}'.format(time,
                                                  unit,
                                                  prec=precision,
                                                  len=len_)
        num = self.autorange(callback)[0]
        raw_timings = self.repeat(repeat, num)
        timings = [i / num for i in raw_timings]
        best = min(timings)
        time = format_time(best)
        if outptype == OutType.STR:
            return ('{} loop{}, best of {}:'
                    ' {} per loop').format(num,
                                           's' if num != 1 else '',
                                           repeat,
                                           time)
        if outptype == OutType.NUM:
            return num, repeat, time
    
    @property
    def units(self):
        return self._units
    
    @units.setter
    def units(self, new_units):
        from numbers import Number
        new_units = list(new_units)
        for scale, unit in new_units:
            if not isinstance(scale, Number) or not str(unit):
                raise TypeError('incompatible units list')
        self._units = [(scale, str(unit)) for scale, unit in new_units]
