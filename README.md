## SwiftNIO Example Apps

The point of this repository is to be a collection of ready-to-use SwiftNIO example apps. The other `apple/swift-nio` repositories contain libraries which do sometimes contain example code but usually not whole applications.

The definition of app includes any sort of application, command line utilities, iOS Apps, macOS GUI applications or whatever you can think of.

### Organisation

Each example application should be fully contained in its own sub-directory together with a `README.md` explaining what the application demonstrates. Each application must be buildable through either `cd AppName && swift build` or `cd AppName && ./build.sh`.

Like all other code in the SwiftNIO project, the license for all the code contained in this repository is the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.html). See also `LICENSE.txt`.


### Quality

Example applications must go through pre-commit code review like all other code in the SwiftNIO project. It is however acceptable to publish demo applications that only work for a subset of the supported platforms if that limitation is clearly documented in the project's `README.md`.


### NIO versions

The [`main`](https://github.com/apple/swift-nio-examples) branch contains the examples for the SwiftNIO 2 family. For the examples working with NIO 1, please use the [`nio-1`](https://github.com/apple/swift-nio-examples/tree/nio-1) branch.
