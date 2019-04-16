import JSONRPC
import NIO

struct Lifx {
    let id: String
    init?(_ object: RPCObject) {
        switch object {
        case .dictionary(let value):
            switch value["_lifx"] ?? RPCObject("") {
            case .dictionary(let value):
                switch value["addr"] ?? RPCObject("") {
                case .string(let value):
                    self.id = value.split(separator: ":").joined()
                default:
                    return nil
                }
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

enum Color: Int, CaseIterable {
    case red = 360
    case orange = 50
    case yellow = 70
    case green = 90
    case blue = 225
    case purple = 280
    case pink = 300
    case white = 0

    init(_ name: String) {
        switch name.lowercased() {
        case "white":
            self = .white
        case "red":
            self = .red
        case "orange":
            self = .orange
        case "yellow":
            self = .yellow
        case "green":
            self = .green
        case "blue":
            self = .blue
        case "purple":
            self = .purple
        case "pink":
            self = .pink
        default:
            self = .white
        }
    }
}

func reset(_ client: TCPClient) {
    off(client, id: "*")
    sleep(1)
    on(client, id: "*")
    sleep(1)
    off(client, id: "*")
}

func list(_ client: TCPClient) -> [Lifx] {
    switch try! client.call(method: "get_light_state", params: RPCObject(["target": "*"])).wait() {
    case .failure(let error):
        fatalError("get_light_state failed with \(error)")
    case .success(let response):
        switch response {
        case .list(let value):
            return value.map { Lifx($0) }.compactMap { $0 }
        default:
            fatalError("unexpected reponse with \(response)")
        }
    }
    return []
}

func on(_ client: TCPClient, id: String, color: Color = .white, transition: Int = 0) {
    let saturation = .white == color ? 0.0 : 1.0
    switch try! client.call(method: "set_light_from_hsbk", params: hsbk(target: id, hue: color.rawValue, saturation: saturation, brightness: 0.1, temperature: 5000, transition: transition)).wait() {
    case .failure(let error):
        fatalError("set_light_from_hsbk failed with \(error)")
    case .success:
        break
    }
    switch try! client.call(method: "power_on", params: RPCObject(["target": id])).wait() {
    case .failure(let error):
        fatalError("power_on failed with \(error)")
    case .success:
        break
    }
}

func off(_ client: TCPClient, id: String) {
    switch try! client.call(method: "power_off", params: RPCObject(["target": id])).wait() {
    case .failure(let error):
        fatalError("power_off failed with \(error)")
    case .success:
        break
    }
}

func show(_ client: TCPClient) {
    let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

    // read lights state
    var bulbs: [Lifx]
    switch try! client.call(method: "get_light_state", params: RPCObject(["target": "*"])).wait() {
    case .failure(let error):
        fatalError("get_light_state failed with \(error)")
    case .success(let response):
        switch response {
        case .list(let value):
            bulbs = value.map { Lifx($0) }.compactMap { $0 }
        default:
            fatalError("unexpected reponse with \(response)")
        }
    }
    if 0 == bulbs.count {
        fatalError("no bulbs found")
    }

    off(client, id: "*")
    sleep(1)

    var bulbIndex = 0
    for _ in 0 ..< bulbs.count * 10 {
        for (index, bulb) in bulbs.enumerated() {
            if index == bulbIndex {
                on(client, id: bulb.id, color: .white, transition: 100)
            } else {
                off(client, id: bulb.id)
            }
        }
        bulbIndex = bulbIndex < bulbs.count - 1 ? bulbIndex + 1 : 0
        usleep(300_000)
    }

    off(client, id: "*")
    sleep(1)

    bulbIndex = 0
    for colorIndex in 0 ..< colors.count {
        for _ in 0 ..< bulbs.count {
            for (index, bulb) in bulbs.enumerated() {
                if index == bulbIndex {
                    on(client, id: bulb.id, color: colors[colorIndex], transition: 100)
                } else {
                    off(client, id: bulb.id)
                }
            }
            bulbIndex = bulbIndex < bulbs.count - 1 ? bulbIndex + 1 : 0
            usleep(300_000)
        }
    }

    off(client, id: "*")
    sleep(1)

    bulbIndex = 0
    var colorIndex = 0
    for _ in 0 ..< bulbs.count * colors.count {
        for (index, bulb) in bulbs.enumerated() {
            if index == bulbIndex {
                on(client, id: bulb.id, color: colors[colorIndex], transition: 100)
                colorIndex = colorIndex < colors.count - 1 ? colorIndex + 1 : 0
            } else {
                off(client, id: bulb.id)
            }
        }
        bulbIndex = bulbIndex < bulbs.count - 1 ? bulbIndex + 1 : 0
        usleep(300_000)
    }

    off(client, id: "*")
    sleep(1)

    var colorsMap: [String: Color] = bulbs.enumerated().reduce(into: [String: Color]()) {
        $0[$1.element.id] = $1.offset < colors.count ? colors[$1.offset] : colors.first!
    }
    while true {
        for bulb in bulbs {
            let clr = colorsMap[bulb.id] ?? colors.first!
            on(client, id: bulb.id, color: clr, transition: 100)
            let newIndex = colors.firstIndex(of: clr)! + 1
            colorsMap[bulb.id] = newIndex < colors.count ? colors[newIndex] : colors.first!
        }
        usleep(300_000)
    }
}

func hsbk(target: String, hue: Int, saturation: Double, brightness: Double, temperature: Int, transition: Int = 0) -> RPCObject {
    assert(hue >= 0 && hue <= 360, "Hue from 0 to 360")
    assert(saturation >= 0 && saturation <= 1, "Saturation from 0 to 1")
    assert(brightness >= 0 && brightness <= 1, "Brightness from 0 to 1")
    assert(temperature >= 2500 && temperature <= 9000, "Temperature in Kelvin from 2500 to 9000")
    //assert (transition >= 0 && transition <= 60000, "Transition duration to this color in ms")
    return RPCObject([RPCObject(target), RPCObject(hue), RPCObject(saturation), RPCObject(brightness), RPCObject(temperature), RPCObject(transition)])
}

let address = ("127.0.0.1", 7000)
let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let client = TCPClient(group: eventLoopGroup, config: TCPClient.Config(framing: .brute))
_ = try! client.connect(host: address.0, port: address.1).wait()

// run command
if CommandLine.arguments.count < 2 {
    fatalError("not enough arguments")
}

switch CommandLine.arguments[1] {
case "reset":
    reset(client)
case "list":
    let bulbs = list(client)
    print("======= bulbs =======")
    bulbs.forEach { print(" \($0)") }
    print("=====================")
case "on":
    if CommandLine.arguments.count < 3 {
        fatalError("not enough arguments")
    }
    on(client, id: CommandLine.arguments[2])
case "off":
    if CommandLine.arguments.count < 3 {
        fatalError("not enough arguments")
    }
    off(client, id: CommandLine.arguments[2])
case "color":
    if CommandLine.arguments.count < 4 {
        fatalError("not enough arguments")
    }
    on(client, id: CommandLine.arguments[2], color: Color(CommandLine.arguments[3]))
case "show":
    show(client)
default:
    fatalError("unknown command \(CommandLine.arguments[1])")
}
// shutdown
try! client.disconnect().wait()
