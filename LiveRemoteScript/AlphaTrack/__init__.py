from __future__ import absolute_import, print_function, unicode_literals
from .AlphaTrack import AlphaTrack


def create_instance(c_instance):
    return AlphaTrack(c_instance)


def exit_instance():
    pass
