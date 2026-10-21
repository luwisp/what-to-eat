package juxiaobao

import juxiaobao.app.*

main(): Int64 {
    startServer(serverConfigFromEnvironment())
    return 0
}
