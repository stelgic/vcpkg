# Full mirror list: https://github.com/msys2/MSYS2-packages/blob/master/pacman-mirrors/mirrorlist.msys
set(Z_VCPKG_ACQUIRE_MSYS_MIRRORS
    # Alternative primary
    "https://repo.msys2.org/"
    # Tier 1
    "https://mirror.yandex.ru/mirrors/msys2/"
    "https://mirrors.tuna.tsinghua.edu.cn/msys2/"
    "https://mirrors.ustc.edu.cn/msys2/"
    "https://mirror.selfnet.de/msys2/"
)

# Downloads the given package
function(z_vcpkg_acquire_msys_download_package out_archive)
    cmake_parse_arguments(PARSE_ARGV 1 "arg" "" "URL;SHA512;FILENAME" "")
    if(DEFINED arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "internal error: z_vcpkg_acquire_msys_download_package passed extra args: ${arg_UNPARSED_ARGUMENTS}")
    endif()

    string(REPLACE "https://repo.msys2.org/" "https://mirror.msys2.org/" all_urls "${arg_URL}")
    foreach(mirror IN LISTS Z_VCPKG_ACQUIRE_MSYS_MIRRORS)
        string(REPLACE "https://mirror.msys2.org/" "${mirror}" mirror_url "${arg_URL}")
        list(APPEND all_urls "${mirror_url}")
    endforeach()

    vcpkg_download_distfile(msys_archive
        URLS ${all_urls}
        SHA512 "${arg_SHA512}"
        FILENAME "${arg_FILENAME}"
        QUIET
    )
    set("${out_archive}" "${msys_archive}" PARENT_SCOPE)
endfunction()

# Declares a package
# Writes to the following cache variables:
#   - Z_VCPKG_MSYS_PACKAGES_AVAILABLE
#   - Z_VCPKG_MSYS_${arg_NAME}_URL
#   - Z_VCPKG_MSYS_${arg_NAME}_SHA512
#   - Z_VCPKG_MSYS_${arg_NAME}_FILENAME
#   - Z_VCPKG_MSYS_${arg_NAME}_DEPS
#   - Z_VCPKG_MSYS_${arg_NAME}_PATCHES
#   - Z_VCPKG_MSYS_${arg_NAME}_DIRECT
#   - Z_VCPKG_MSYS_${arg_NAME}_PROVIDES
#   - Z_VCPKG_MSYS_${alias}_PROVIDED_BY
function(z_vcpkg_acquire_msys_declare_package)
    cmake_parse_arguments(PARSE_ARGV 0 arg "DIRECT" "NAME;URL;SHA512" "DEPS;PATCHES;PROVIDES")

    if(DEFINED arg_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "internal error: z_vcpkg_acquire_msys_declare_package passed extra args: ${arg_UNPARSED_ARGUMENTS}")
    endif()
    foreach(required_arg IN ITEMS URL SHA512)
        if(NOT DEFINED arg_${required_arg})
            message(FATAL_ERROR "internal error: z_vcpkg_acquire_msys_declare_package requires argument: ${required_arg}")
        endif()
    endforeach()

    if(arg_DIRECT)
        if(NOT arg_NAME)
            message(FATAL_ERROR "internal error: z_vcpkg_acquire_msys_declare_package requires argument: NAME")
        endif()
        get_filename_component(filename "${arg_URL}" NAME)
    else()
        if(NOT arg_URL MATCHES [[^https://mirror\.msys2\.org/.*/(([^/]*)-[^-/]+-[^-/]+-[^-/]+\.pkg\.tar\.(xz|zst))$]])
            message(FATAL_ERROR "internal error: regex does not match supplied URL to vcpkg_acquire_msys: ${arg_URL}")
        endif()
        set(filename "msys2-${CMAKE_MATCH_1}")
        if(NOT DEFINED arg_NAME)
            set(arg_NAME "${CMAKE_MATCH_2}")
        endif()
        if(Z_VCPKG_MSYS_${arg_NAME}_DIRECT)
            return()
        endif()
        if(arg_NAME IN_LIST Z_VCPKG_MSYS_PACKAGES_AVAILABLE)
            message(FATAL_ERROR "Redeclaration of package '${arg_NAME}'")
        endif()
    endif()

    list(APPEND Z_VCPKG_MSYS_PACKAGES_AVAILABLE "${arg_NAME}")
    set(Z_VCPKG_MSYS_PACKAGES_AVAILABLE "${Z_VCPKG_MSYS_PACKAGES_AVAILABLE}" CACHE INTERNAL "")
    set(Z_VCPKG_MSYS_${arg_NAME}_URL "${arg_URL}" CACHE INTERNAL "")
    set(Z_VCPKG_MSYS_${arg_NAME}_SHA512 "${arg_SHA512}" CACHE INTERNAL "")
    set(Z_VCPKG_MSYS_${arg_NAME}_FILENAME "${filename}" CACHE INTERNAL "")
    set(Z_VCPKG_MSYS_${arg_NAME}_DEPS "${arg_DEPS}" CACHE INTERNAL "")
    set(Z_VCPKG_MSYS_${arg_NAME}_PATCHES "${arg_PATCHES}" CACHE INTERNAL "")
    set(Z_VCPKG_MSYS_${arg_NAME}_DIRECT "${arg_DIRECT}" CACHE INTERNAL "")
    set(Z_VCPKG_MSYS_${arg_NAME}_PROVIDES "${arg_PROVIDES}" CACHE INTERNAL "")
    foreach(name IN LISTS arg_PROVIDES)
        set(Z_VCPKG_MSYS_${name}_PROVIDED_BY "${arg_NAME}" CACHE INTERNAL "")
    endforeach()
endfunction()

# Collects all required packages to satisfy the given input set
# Writes to the following cache variables:
#   - Z_VCPKG_MSYS_<name>_ARCHIVE
function(z_vcpkg_acquire_msys_download_packages)
    cmake_parse_arguments(PARSE_ARGV 0 "arg" "" "OUT_UNKNOWN;OUT_RESOLVED" "PACKAGES")
    set(backlog "${arg_PACKAGES}")
    list(REMOVE_DUPLICATES backlog)

    list(FILTER arg_PACKAGES EXCLUDE REGEX "^mingw64")
    if(NOT arg_PACKAGES STREQUAL "" AND NOT "msys2-runtime" IN_LIST arg_PACKAGES)
        list(APPEND backlog "msys2-runtime")
    endif()

    set(unknown "")
    set(resolved "")
    set(need_msys_runtime 0)
    while(NOT backlog STREQUAL "")
        list(POP_FRONT backlog name)
        if(DEFINED Z_VCPKG_MSYS_${name}_PROVIDED_BY AND NOT name IN_LIST Z_VCPKG_MSYS_PACKAGES_AVAILABLE)
            set(name "${Z_VCPKG_MSYS_${name}_PROVIDED_BY}")
            if(name IN_LIST resolved)
                continue()
            endif()
        endif()
        if(NOT name IN_LIST Z_VCPKG_MSYS_PACKAGES_AVAILABLE)
            list(APPEND unknown "${name}")
            continue()
        endif()
        list(APPEND resolved "${name}")
        list(REMOVE_ITEM Z_VCPKG_MSYS_${name}_DEPS ${resolved} ${backlog})
        list(APPEND backlog ${Z_VCPKG_MSYS_${name}_DEPS})

        z_vcpkg_acquire_msys_download_package(archive
            URL "${Z_VCPKG_MSYS_${name}_URL}"
            SHA512 "${Z_VCPKG_MSYS_${name}_SHA512}"
            FILENAME "${Z_VCPKG_MSYS_${name}_FILENAME}"
        )
        set(Z_VCPKG_MSYS_${name}_ARCHIVE "${archive}" CACHE INTERNAL "")
    endwhile()
    if(DEFINED arg_OUT_UNKNOWN)
        set("${arg_OUT_UNKNOWN}" "${unknown}" PARENT_SCOPE)
    endif()
    if(DEFINED arg_OUT_RESOLVED)
        set("${arg_OUT_RESOLVED}" "${resolved}" PARENT_SCOPE)
    endif()
endfunction()

# Returns a stable collection of hashes, regardless of package order
function(z_vcpkg_acquire_msys_collect_hashes out_hash)
    cmake_parse_arguments(PARSE_ARGV 1 "arg" "" "" "PACKAGES")
    list(SORT arg_PACKAGES)
    set(result "")
    foreach(name IN LISTS arg_PACKAGES)
        if(NOT DEFINED Z_VCPKG_MSYS_${name}_SHA512)
            message(FATAL_ERROR "SHA512 unknown for '${name}'.")
        endif()
        string(APPEND result "${Z_VCPKG_MSYS_${name}_SHA512}")
        foreach(patch IN LISTS Z_VCPKG_MSYS_${name}_PATCHES)
            file(SHA512 "${patch}" patch_sha)
            string(APPEND result "${patch_sha}")
        endforeach()
    endforeach()
    set(${out_hash} "${result}" PARENT_SCOPE)
endfunction()

function(vcpkg_acquire_msys out_msys_root)
    cmake_parse_arguments(PARSE_ARGV 1 "arg"
        "NO_DEFAULT_PACKAGES;Z_ALL_PACKAGES"
        "Z_DECLARE_EXTRA_PACKAGES_COMMAND"
        "PACKAGES;DIRECT_PACKAGES"
    )

    if(DEFINED arg_UNPARSED_ARGUMENTS)
        message(WARNING "vcpkg_acquire_msys was passed extra arguments: ${arg_UNPARSED_ARGUMENTS}")
    endif()

    z_vcpkg_acquire_msys_declare_all_packages()
    if(NOT "${arg_Z_DECLARE_EXTRA_PACKAGES_COMMAND}" STREQUAL "")
        cmake_language(CALL "${arg_Z_DECLARE_EXTRA_PACKAGES_COMMAND}")
    endif()
    set(requested "${arg_PACKAGES}")
    if(arg_Z_ALL_PACKAGES)
        set(requested "${Z_VCPKG_MSYS_PACKAGES_AVAILABLE}")
    elseif(NOT arg_NO_DEFAULT_PACKAGES)
        list(APPEND requested bash coreutils file gawk grep gzip diffutils make pkgconf sed)
    endif()

    if(DEFINED arg_DIRECT_PACKAGES AND NOT arg_DIRECT_PACKAGES STREQUAL "")
        list(LENGTH arg_DIRECT_PACKAGES direct_packages_length)
        math(EXPR direct_packages_parity "${direct_packages_length} % 2")
        math(EXPR direct_packages_number "${direct_packages_length} / 2")
        math(EXPR direct_packages_last "${direct_packages_number} - 1")

        if(direct_packages_parity EQUAL 1)
            message(FATAL_ERROR "vcpkg_acquire_msys(... DIRECT_PACKAGES ...) requires exactly pairs of URL/SHA512")
        endif()

        set(direct_packages "")
        # direct_packages_last > direct_packages_number - 1 > 0 - 1 >= 0, so this is fine
        foreach(index RANGE "${direct_packages_last}")
            math(EXPR url_index "${index} * 2")
            math(EXPR sha512_index "${url_index} + 1")
            list(GET arg_DIRECT_PACKAGES "${url_index}" url)
            list(GET arg_DIRECT_PACKAGES "${sha512_index}" sha512)
            get_filename_component(filename "${url}" NAME)
            if(NOT filename MATCHES "^(.*)-[^-]+-[^-]+-[^-]+\.pkg\.tar\..*$")
                message(FATAL_ERROR "Cannot determine package name for '${filename}'")
            endif()
            set(pkg_name "${CMAKE_MATCH_1}")
            z_vcpkg_acquire_msys_declare_package(
                NAME "${pkg_name}"
                URL "${url}"
                SHA512 "${sha512}"
                DIRECT
            )
            list(APPEND direct_packages "${pkg_name}")
        endforeach()
        list(INSERT requested 0 ${direct_packages})
    endif()
 
    z_vcpkg_acquire_msys_download_packages(
        PACKAGES ${requested}
        OUT_RESOLVED resolved
        OUT_UNKNOWN unknown
    )
    if(NOT unknown STREQUAL "")
        message(FATAL_ERROR "Unknown packages were required for vcpkg_acquire_msys(${requested}): ${unknown}
This can be resolved by explicitly passing URL/SHA pairs to DIRECT_PACKAGES.")
    endif()
    set(Z_VCPKG_MSYS_PACKAGES_RESOLVED "${resolved}" CACHE INTERNAL "Export for CI")

    z_vcpkg_acquire_msys_collect_hashes(hashes PACKAGES ${resolved})
    string(SHA512 total_hash "${hashes}")
    string(SUBSTRING "${total_hash}" 0 16 total_hash)
    set(path_to_root "${DOWNLOADS}/tools/msys2/${total_hash}")

    if(NOT EXISTS "${path_to_root}")
        file(REMOVE_RECURSE "${path_to_root}.tmp")
        file(MAKE_DIRECTORY "${path_to_root}.tmp/tmp")
        foreach(name IN LISTS resolved)
            file(ARCHIVE_EXTRACT
                INPUT "${Z_VCPKG_MSYS_${name}_ARCHIVE}"
                DESTINATION "${path_to_root}.tmp"
            )
            if(Z_VCPKG_MSYS_${name}_PATCHES)
                z_vcpkg_apply_patches(
                    SOURCE_PATH "${path_to_root}.tmp"
                    PATCHES ${Z_VCPKG_MSYS_${name}_PATCHES}
                )
            endif()
        endforeach()
        file(RENAME "${path_to_root}.tmp" "${path_to_root}")
    endif()
    # Due to skipping the regular MSYS2 installer,
    # some config files need to be established explicitly.
    if(NOT EXISTS "${path_to_root}/etc/fstab")
        # This fstab entry removes the cygdrive prefix from paths.
        file(WRITE "${path_to_root}/etc/fstab" "none  /  cygdrive  binary,posix=0,noacl,user  0  0")
    endif()
    message(STATUS "Using msys root at ${path_to_root}")
    set("${out_msys_root}" "${path_to_root}" PARENT_SCOPE)
endfunction()

# Expand this while CMAKE_CURRENT_LIST_DIR is for this file.
set(Z_VCPKG_AUTOMAKE_CLANG_CL_PATCH "${CMAKE_CURRENT_LIST_DIR}/compile_wrapper_consider_clang-cl.patch")

macro(z_vcpkg_acquire_msys_declare_all_packages)
    set(Z_VCPKG_MSYS_PACKAGES_AVAILABLE "" CACHE INTERNAL "")

    # The following list can be updated via test port vcpkg-ci-msys2[update-all].
    # Upstream binary package information is available via
    # https://packages.msys2.org/search?t=binpkg&q=<Pkg>

    # msys subsystem
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/autoconf-wrapper-20240607-1-any.pkg.tar.zst"
        SHA512 e91768eaa3e9ad849c8ab2177593503fb85cda623adfe2e21eb5a34dd58c2c6686bee42cb1d1a6cfe8ae5727fb10edc5e1229e56f96091c25cae4eecc03f191a
        PROVIDES autoconf
        DEPS autoconf2.72 bash sed
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/autoconf2.72-2.72-3-any.pkg.tar.zst"
        SHA512 307751b00b6a9729673d0af35ccf327041880f20498143100053a9d914927e86dd20a4aa4cd9e83e3d4e7e27c2d068cfc0313c6cab4f103955e4dafede22f4d0
        DEPS awk bash diffutils m4 perl sed
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/autoconf-archive-2023.02.20-1-any.pkg.tar.zst"
        SHA512 0dbdba67934402eeb974e6738eb9857d013342b4e3a11200710b87fbf085d5bebf49b29b6a14b6ff2511b126549919a375b68f19cc22aa18f6ba23c57290ac72
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/automake-wrapper-20240607-1-any.pkg.tar.zst"
        SHA512 59c219019a776d36cf37a755fdb1c60b0bfd4ef8ec4dc55d2ba5de00e85686cc480d05689d8fa23532615000f3371702c2b2fe31a0f18f92df9f4353202a6e23
        PROVIDES automake
        DEPS automake1.16 bash gawk
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/automake1.16-1.16.5-1-any.pkg.tar.zst"
        SHA512 62c9dfe28d6f1d60310f49319723862d29fc1a49f7be82513a4bf1e2187ecd4023086faf9914ddb6701c7c1e066ac852c0209db2c058f3865910035372a4840a
        DEPS bash perl
        PATCHES "${Z_VCPKG_AUTOMAKE_CLANG_CL_PATCH}"
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/bash-5.2.037-1-x86_64.pkg.tar.zst"
        SHA512 c93ea45d4dd603d5cef42b599b4e0ff40b064bfd277eaf6933be35105e085155ebd63b732a2fa703e3878dc26bc288b09a5dfe355531237e3b20c27e1fc12215
        PROVIDES sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/binutils-2.43.1-1-x86_64.pkg.tar.zst"
        SHA512 fb4ceb5f6b472923f654aa320401b7d65063c62c8f4c284996ac1e7f3091e117dafb1d600df164466bc0b56fb5a4d13558b05f707dd91e7801c37df7e9346a5e
        DEPS libiconv libintl zlib
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/bzip2-1.0.8-4-x86_64.pkg.tar.zst"
        SHA512 1d2ce42c6775c0cb0fe9c2863c975fd076579131d0a5bce907355315f357df4ee66869c9c58325f5b698f3aba2413b2823deda86dd27fdb6e2e5e5d4de045259
        DEPS libbz2
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/coreutils-8.32-5-x86_64.pkg.tar.zst"
        SHA512 63f99348e654440458f26e9f52ae3289759a5a03428cf2fcf5ac7b47fdf7bf7f51d08e3346f074a21102bee6fa0aeaf88b8ebeba1e1f02a45c8f98f69c8db59c
        DEPS libiconv libintl gmp
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/diffutils-3.10-1-x86_64.pkg.tar.zst"
        SHA512 7ed406370a699be98bff4eeb156a063de80ac8e332fb1873639e0b95b2e72e626351e24c5ca0021af9c0e56c4a3d91bd6669e6245b21c9d4ebdbb36888d8e39d
        DEPS libiconv libintl sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/file-5.46-1-x86_64.pkg.tar.zst"
        SHA512 87fdc561e21e94f68c1191c3e6129bd459146b1ca006aeda0ec469b642bc5354597371dcc9c5decfba8d6f19607ee00b596e426b95db03125d839642ac414eea
        DEPS gcc-libs libbz2 liblzma libzstd zlib
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/findutils-4.10.0-2-x86_64.pkg.tar.zst"
        SHA512 d817f31b1130f73ababf004585e540c2adc14b2517ae350c73ef3f9b6c25b92ee377b24f6695980fd815c91fa8c870e574633092bd9436b7dbfb30b9d782b5fc
        DEPS libintl libiconv
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/gawk-5.3.1-1-x86_64.pkg.tar.zst"
        SHA512 01baeb86f0f604f9eb4e9da5c58e02a1fdc52943a62f66b1c14e1cdf72fb252936d63b25c60e992c0aab8ea146ff6dc9bb15b750bd21f803e4dcb31f5965c5bb
        PROVIDES awk
        DEPS libintl libreadline mpfr sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/gcc-libs-13.3.0-1-x86_64.pkg.tar.zst"
        SHA512 f38b33ecc56923bff2e43d7c0fc8a79c752feeb6af9d49ff4bdd919e04ca54e7c6a0710e9c55fc700ad53eba6c4670973d7cc867971a40bcbe3c82932a7d3f38
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/gettext-0.22.4-1-x86_64.pkg.tar.zst"
        SHA512 7bd1dc50df8a973a075286fdf115fa30c8a78aa23d2845e2bdeb6068bf3391321d9b3ce3241626453bb660d1a57563bea44eebadf81cb2f98f15fbaf266648ec
        DEPS libasprintf libgettextpo libintl
    )
    # This package shouldn't be a here
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/gettext-devel-0.22.4-1-x86_64.pkg.tar.zst"
        SHA512 e7748736014b0aa47f2bc740189a5e8e1bcc99a82ccd02d6f75e226b041704e4f353107df175c0547651a05f5a352ec474a7af693fb33d42a8885e47ac371d2e
        DEPS gettext # libiconv-devel
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/gmp-6.3.0-1-x86_64.pkg.tar.zst"
        SHA512 d4e8549e55d4088eca30753f867bf82d9287955209766f488f2a07ecc71bc63ef2c50fcc9d47470ea3b0d2f149f1648d9c2453e366e3eb2c2e2d60939f311a40
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/grep-1~3.0-6-x86_64.pkg.tar.zst"
        SHA512 79b4c652082db04c2ca8a46ed43a86d74c47112932802b7c463469d2b73e731003adb1daf06b08cf75dc1087f0e2cdfa6fec0e8386ada47714b4cff8a2d841e1
        DEPS libiconv libintl libpcre sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/gzip-1.13-1-x86_64.pkg.tar.zst"
        SHA512 4dbcfe5df7c213b10f003fc2a15123a5ed0d1a6d09638c467098f7b7db2e4fdd75a7ceee03b3a26c2492ae485267d626db981c5b9167e3acb3d7436de97d0e97
        DEPS bash
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/libasprintf-0.22.4-1-x86_64.pkg.tar.zst"
        SHA512 06f353d2020d1e7168f4084e9fc17856a158a67a61098314e4b1d7db075542eb29dfe8a84bd154dad28942ee8eaae1e13a6510a4d2caab4509d9f3ea22db6d87
        DEPS gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/libbz2-1.0.8-4-x86_64.pkg.tar.zst"
        SHA512 5a7be6d04e55e6fb1dc0770a8c020ca24a317807c8c8a4813146cd5d559c12a6c61040797b062e441645bc2257b390e12dd6df42519e56278a1fe849fe76a1c4
        DEPS gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/libgettextpo-0.22.4-1-x86_64.pkg.tar.zst"
        SHA512 7552bc873331f07a4c006f27fe9f72186eed9717d68c4cbf54a75ff65c9445f874c43ccced2f9fa75ff1602c1209f6f1f4335a6ae6bf9bd5e951292584db7539
        DEPS gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/libiconv-1.18-1-x86_64.pkg.tar.zst"
        SHA512 77979ed35af45aa5bb7fb6b07d649e8eafa69ebdc8e421c2a7bf69ee567f814b38623a12be0736fb56c17c0aeff69ba769bc52110f62f8e5fdc5bcf334d88d44
        DEPS gcc-libs libintl
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/libintl-0.22.4-1-x86_64.pkg.tar.zst"
        SHA512 07f41f7fa53967bb5b0aca72255c70d7aeed58ea86b67bd0e765e08c20c50187ef2e775b630c0d48b3afbe62203754f7e8653a5f2e1a87a38b4af5753c7bd232
        DEPS gcc-libs libiconv
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/liblzma-5.6.3-1-x86_64.pkg.tar.zst"
        SHA512 9fea23590973d5d2eea6da134ae4d10cd5a989babf135778de15ae0d5f28aad58f74485339d1e76187e3496993d26f4c243256d20dd7a0d77e9ebdc5ed56f124
        # This package installs only a DLL. No extra deps.
        DEPS # gettext libiconv sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/libpcre-8.45-4-x86_64.pkg.tar.zst"
        SHA512 e1eb5cb38dce22012527bba2e92f908bf23c7725d77dcbd7fa14597af0f5b413319e0a7dd66555370afffc3b55d6074b8b83fd3c384d31ac505b74db246d54ac
        DEPS gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/libreadline-8.2.013-1-x86_64.pkg.tar.zst"
        SHA512 31a649a3b694434ce6a1c70ff5fa208a99acf323a6a1b521e1ce8b1cc0cdb9b63df3200ab497ba0e477d6ab61721bdfb133a90156fd88295b4ff9ff2551866cd
        DEPS ncurses
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/libtool-2.5.4-1-x86_64.pkg.tar.zst"
        SHA512 65bdd278c19a6f32094d9944ac87418f38966e453f5fca60b2e00966731af88b119b94ef3cb6a68a9fd9a183f846d08a6524b9f273d311987acc308e84e3cf00
        DEPS sh tar
             # extra deps which are really needed
             awk findutils grep sed
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/libxcrypt-4.4.36-1-x86_64.pkg.tar.zst"
        SHA512 457320daebd1aa45461788fb52dd4772fe91c34902201fac81d94ee2cbbfa216b02b3831a3e32a5ac638a3f12ac31fcec94ee95b19696fec6624e10e3dc5ffff
        DEPS gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/libzstd-1.5.6-1-x86_64.pkg.tar.zst"
        SHA512 ec13dde8cdb16ea48df6ddd172d60d913446907933f47846d2631c6f52dc874fae0dbf7cab4c0d81b3e643a0483dcc7fe316a429fa79ba06bbc29754fc9afb52
        DEPS gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/m4-1.4.19-2-x86_64.pkg.tar.zst"
        SHA512 7471099ba7e3b47e5b019dc0e563165a8660722f2bbd337fb579e6d1832c0e7dcab0ca9297c4692b18add92c4ad49e94391c621cf38874e2ff63d4f926bac38c
        DEPS bash gcc-libs libiconv
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/make-4.4.1-2-x86_64.pkg.tar.zst"
        SHA512 b55caaf0d54b784b5dffcbb75a1862fc7359b91caa1e60234e208de03c74159fd003d68f5dddd387adef752bb13805e654f17ec5cb6add51546b9e30a1091b61
        DEPS libintl sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/mpfr-4.2.1-1-x86_64.pkg.tar.zst"
        SHA512 7417bb02a0f1073b8c1a64732463ec178d28f75eebd9621d02117cda1d214aff3e28277bd20e1e4731e191daab26e38333ace007ed44459ce3e2feae27aedc00
        DEPS gmp
    )
    if(X_VCPKG_USE_MSYS2_RUNTIME_3.4) # temporary option, for Windows 7.0 and 8.0, or in case of regressions
        z_vcpkg_acquire_msys_declare_package(
            URL "https://mirror.msys2.org/msys/x86_64/msys2-runtime-3.4-3.4.10-2-x86_64.pkg.tar.zst"
            SHA512 3fa087d4eb4e260785b81d5b6f4400ec128a83ff940da732bf147dfde457224573fa467e735b63c9a138872f5c9830f3684f824b2aa5d344fb95dfb91632f832
            PROVIDES msys2-runtime
        )
    else()
        z_vcpkg_acquire_msys_declare_package(
            URL "https://mirror.msys2.org/msys/x86_64/msys2-runtime-3.5.4-8-x86_64.pkg.tar.zst"
            SHA512 68b7b50b2923e685f2068492f71634b226bb350ef0ede629d37bb049ec517575afb5f28d1097c7dd48407ff5cf2972b252e6d6f3e988479a2f68dbced9c9fb9e
        )
    endif()
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/ncurses-6.5.20240831-2-x86_64.pkg.tar.zst"
        SHA512 ff84849e3857e31fd4f3acc48e8a9bc2fa6ff226f848636c206fb322e7c49de9677c24784575ad5d13620f31d6203739b0f7ab068081bef0d8ab873c4473ee4d
        DEPS gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/patch-2.7.6-2-x86_64.pkg.tar.zst"
        SHA512 eb484156e6e93da061645437859531f7b04abe6fef9973027343302f088a8681d413d87c5635a10b61ddc4a3e4d537af1de7552b3a13106639e451b95831ec91
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/perl-5.38.2-2-x86_64.pkg.tar.zst"
        SHA512 1d1cff89a0f0b47eb5bea51974a092b42a9c05634391bf2056dcd38557d8b97a3f6e697fb2bbf421beea780f132d8d13ff8e0cec22b24f99811657857691a815
        DEPS coreutils libxcrypt sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/pkgconf-2.3.0-1-x86_64.pkg.tar.zst"
        SHA512 38ad69f7da3bfd81282cbb488cb06fe2e5a2d075a7b96499d588a4c398d6778b4a345807d79ac31520b793194f5466ebdf1d00d886c7fa16c5a347230866b11a
        PROVIDES pkg-config
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/sed-4.9-1-x86_64.pkg.tar.zst"
        SHA512 8006a83f0cc6417e3f23ffd15d0cbca2cd332f2d2690232a872ae59795ac63e8919eb361111b78f6f2675c843758cc4782d816ca472fe841f7be8a42c36e8237
        DEPS libintl sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/tar-1.35-2-x86_64.pkg.tar.zst"
        SHA512 86269fe17729e5381f8236a0251088110725c3eb930215b8378b6673e5ee136847997bb6a667fe0398b65b85e3f3a7e4679a0fd4bb2ebcb9429a5d7273a02d54
        DEPS libiconv libintl sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/texinfo-7.1-2-x86_64.pkg.tar.zst"
        SHA512 10edea1d3e2720afd47f0ff77ba47849b3eaf5d62d6025c3bce1d683302ae11126e7ee7b26751d1a6a66bc86a4c09021feb373434b1808441897e02245235c7b
        DEPS perl sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/unzip-6.0-3-x86_64.pkg.tar.zst"
        SHA512 1d6df49e826617ef3d3976be33361e189d8a5aee3a33ae79474fd08ca44ebd113981e6ba25c968b3cf5fb9826edd42dee21a97261cbc86fd8b143c950ba1f357
        DEPS bash libbz2
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/which-2.21-4-x86_64.pkg.tar.zst"
        SHA512 5323fd6635093adf67c24889f469e1ca8ac969188c7f087244a43b3afa0bf8f14579bd87d9d7beb16a7cd61a5ca1108515a46b331868b4817b35cebcb4eba1d1
        DEPS sh
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/xz-5.6.2-1-x86_64.pkg.tar.zst"
        SHA512 b26bbe3c434314828410ba0843cf03210c97a441a2657ba5835a4bfa88897396b05ddd263fbe8938fcb738c20e7322b92a12062dd24ee6dba2b041626e172d3d
        DEPS libiconv libintl liblzma
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/msys/x86_64/zlib-1.3.1-1-x86_64.pkg.tar.zst"
        SHA512 a432b0f927d342b678df706487595eff1b780371548933f956adcf697eea11ddbca2863d9d9fb88675a7040dcfddab56f8f71a8ae4d0cd4969e715545c77e87c
        DEPS gcc-libs
    )

    # mingw64 subsystem
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-bzip2-1.0.8-3-any.pkg.tar.zst"
        SHA512 fb1ae524d7b04e1f35c3101c318136dbe08da8093bda98f6aea7e6c2564fec5f8533fb61cac5001b6425105cd982511964ec04099c6651f990dc3b8baf7f7057
        DEPS mingw-w64-x86_64-gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-ca-certificates-20240203-1-any.pkg.tar.zst"
        SHA512 9b1ace77623ea69155112df2aa60dbc83f0dac0db25a2db5f99c40a472e974d6b1fc54b61b71fd57e4166e5741255145da2b19617b1d4a632f1284c5b8d5ca82
        DEPS mingw-w64-x86_64-p11-kit
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-expat-2.6.2-1-any.pkg.tar.zst"
        SHA512 f6cd5f677e488b2fefebe7b8747db451f5967fb4a481496bc703799ec35c189a35f8d7ae2f7b676ba7b325a1115db81f21ed998fe474c153a0a82f3eb180db07
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gcc-libgfortran-14.1.0-3-any.pkg.tar.zst"
        SHA512 5e6d5ba49ebccf2f3b666bec46f0f896971c434be74871d0a81e667d8a5b4f244940821476ac2b5e1765460bd98e259f90752f67fce0af7a6c57d8ca60702c1b
        PROVIDES mingw-w64-x86_64-fc-libs
        DEPS mingw-w64-x86_64-gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gcc-libs-14.1.0-3-any.pkg.tar.zst"
        SHA512 df46139c35b67389fb055d2417ae92e9539920a7ab48618dc4a36a9d1d0b95702c9ee99bd0c5db7cdfbb91e9d3daae1a97ef07cf27efd845ffffd24f513fd01c
        PROVIDES mingw-w64-x86_64-omp
        DEPS mingw-w64-x86_64-libwinpthread
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gettext-runtime-0.22.5-2-any.pkg.tar.zst"
        SHA512 813eb17f9e03267f1a15b0062777bb1cf4cf51b2319aa0e9b6c6a353f47132faab7d7530c1ff19425607c5dabe8af3aee2847ba2e0768056b5834447f491ae73
        DEPS mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-libiconv
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-gmp-6.3.0-2-any.pkg.tar.zst"
        SHA512 38ab150051d787e44f1c75b3703d6c8deb429d244acb2a973ee232043b708e6c9e29a1f9e28f12e242c136d433e8eb5a5133a4d9ac7b87157a9749a8d215d2f0
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libffi-3.4.6-1-any.pkg.tar.zst"
        SHA512 49c4d22e4e08f86eb77946b90fcc8d28e56b3565179187c527a1fa6dfb17ac7dd0d513748755a908467539e7d7e733556bda132c223348b2dc074c6e7dc6b31c
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libiconv-1.18-1-any.pkg.tar.zst"
        SHA512 7aed58286d279699dede96c74e649cea7b78942e51350d277aca9272351d3b645ecfd129b5bbafd40f7e95bfc0187c9df118eca47f2cb795811752a18bcb3745
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libsystre-1.0.1-5-any.pkg.tar.zst"
        SHA512 10ea2bacebb8b05c642f34c0ecf61710b9f1906615851825d1104d0e25b1a911f7541a3068b97de2eb71aa13d6963f61c7fdf051c5582e0868a6f90b93f7aa77
        PROVIDES mingw-w64-x86_64-libgnurx
        DEPS mingw-w64-x86_64-libtre
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libtasn1-4.19.0-1-any.pkg.tar.zst"
        SHA512 761a7c316914d7f98ec6489fb4c06d227e5956d50f2e233ad9be119cfd6301f6b7e4f872316c0bae3913268c1aa9b224b172ab94130489fbd5d7269ff9064cfb
        DEPS mingw-w64-x86_64-gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libtre-git-r177.07e66d0-2-any.pkg.tar.zst"
        SHA512 a21a03fd446707f748f4101e723f71d5f2c93c736d86205dc9eee6681d1bb1248283b8921f897391b56143d8dcf6be29cf8c2c57abcf32e1e4d0b2ea2309a790
        PROVIDES mingw-w64-x86_64-libtre
        DEPS mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-gettext-runtime
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-libwinpthread-git-12.0.0.r32.gf977e1c38-1-any.pkg.tar.zst"
        SHA512 7f12352f3f737d7822ea546394f8661e1f56df136af6d68fe21060597d3aee329c2a9bcd1cfc159ea5afc92752da04591f63c4e36f2106cf2d2c84c4d8592421
        PROVIDES mingw-w64-x86_64-libwinpthread
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-mpc-1.3.1-2-any.pkg.tar.zst"
        SHA512 3fe183d4af3b3935a4394502eab75a8f7b7692f551fd44e54c67935a4691388d23a021ee1147f0345ed27ffe8a8db3e9e7e37caf2348df3413e0acd519c12a0c
        DEPS mingw-w64-x86_64-gmp mingw-w64-x86_64-mpfr
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-mpdecimal-4.0.0-1-any.pkg.tar.zst"
        SHA512 a5975bb5b2ee8e28de986fa8951aa023a55ab54a8c70260dfd54437abeb5f9220b01463b200a228c46ca5ba84ea6373a791b087c32fd41a066b4524892caf282
        DEPS mingw-w64-x86_64-gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-mpfr-4.2.1-2-any.pkg.tar.zst"
        SHA512 03a727e1622b09ed0b6e0cb93a6b1040c31c9504c3f14bd1a2e12b8293153609796bc99882393b343c4d96e45f402f847317a3a65212b972ff96a964e5e52815
        DEPS mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-gmp
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-ncurses-6.5.20240831-1-any.pkg.tar.zst"
        SHA512 6ec005bae6cbd6bbd6e708f1b11ec0ff8f604d771bc0ec13c903dfd1374b9e46ec005bae6cbd6bbd6e708f1b11ec0ff8f604d771bc0ec13c903dfd1374b9e40db9925232a83f5640fa2856756161094326bf822f7b4f0e4941d391f6cce05c40db9925232a83f5640fa2856756161094326bf822f7b4f0e4941d391f6cce05c4
        DEPS mingw-w64-x86_64-libsystre
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-openblas-0.3.27-1-any.pkg.tar.zst"
        SHA512 448e2a53dac79badd0350db82b765ee3cd585bf11abe36b3854a32a4bb28d7aa1dcc3dd9de9186e2fed03674c51889102fe766e1412ce6bda88719a74ce4d9b5
        PROVIDES mingw-w64-x86_64-OpenBLAS
        DEPS mingw-w64-x86_64-gcc-libgfortran mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-libwinpthread mingw-w64-x86_64-omp
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-openssl-3.3.1-1-any.pkg.tar.zst"
        SHA512 47d9a1f02d0537b869a1685e8c80e3aedd6505250acab53697f27c8e1588c16a5a9001ffc3574ef71f511e1189d027e1fb603d816d43cd1f4c0c93b4cd42b531
        #DEPS mingw-w64-x86_64-ca-certificates mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-zlib
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-p11-kit-0.25.3-2-any.pkg.tar.zst"
        SHA512 81e62ad4b1bdf7da3b2de20a3a444b2a30a7b38dda8df41ca7e8baed0954a335cc9594ddd577f4ea5b6000d945348dc7d0364c9408e8a3e3afef34cc5c083c85
        DEPS mingw-w64-x86_64-gettext-runtime mingw-w64-x86_64-libffi mingw-w64-x86_64-libtasn1
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-python-3.11.9-1-any.pkg.tar.zst"
        SHA512 67f35ee599a467788eeef75c462a353c31c011d77f567563c17957d4a199bfbb59ed281f46abf76c1078e710afa17f94bc1326abb30fa7dc67ee38e3ffb25181
        PROVIDES mingw-w64-x86_64-python3 mingw-w64-x86_64-python3.11
        DEPS mingw-w64-x86_64-bzip2 mingw-w64-x86_64-expat mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-libffi mingw-w64-x86_64-mpdecimal mingw-w64-x86_64-ncurses mingw-w64-x86_64-openssl mingw-w64-x86_64-sqlite3 mingw-w64-x86_64-tcl mingw-w64-x86_64-tk mingw-w64-x86_64-xz mingw-w64-x86_64-zlib
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-python-numpy-1.26.4-1-any.pkg.tar.zst"
        SHA512 9d111c10a94d36eab0bf3227a02068ff7845a00db1ae05bba6a6fb55e6503394ba6c0958ce4491cbcfca79e92b3d49f4f567ca901761fa1303718b7ce75b9234
        PROVIDES mingw-w64-x86_64-python3-numpy
        DEPS mingw-w64-x86_64-openblas mingw-w64-x86_64-python
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-readline-8.2.010-1-any.pkg.tar.zst"
        SHA512 ade6caf9e97e762cb2a129a838e1b73e4a2cc4488a7db5c1b6a3ec5db7206d9108a9a7fc5e0e6d7099f26d15ddf71238006dd09467ad2a7617ad9dd925ea04e2
        DEPS mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-termcap
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-sqlite3-3.46.0-1-any.pkg.tar.zst"
        SHA512 5c6d2ff0ccf0e209ed3a8f526064e22c05abb405b9329da8c5a378f7076b4e475fff5a760a353f22250c5289cf792ed4b988ddadc3e6e68b46dac0ab90de1712
        PROVIDES mingw-w64-x86_64-sqlite mingw-w64-x86_64-sqlite-analyzer
        DEPS mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-readline mingw-w64-x86_64-tcl mingw-w64-x86_64-zlib
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-termcap-1.3.1-7-any.pkg.tar.zst"
        SHA512 2610355be441fd933f660f8181a5ad074057361a9aadeaad85961230dcf6df5d5165b94ccf9887144c91812485be57c2d79f39e8191ff525889bdff042d34ce6
        DEPS mingw-w64-x86_64-gcc-libs
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-tcl-8.6.13-1-any.pkg.tar.zst"
        SHA512 e143405ed45da7986d30d2f14bde9dff16fb0ea85a01df45d15cbe8fc52065f5efcb22f8da98962022efbfee3a704fc20e38839ec448cdbb5809336b6b97d550
        DEPS mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-zlib
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-tk-8.6.13-1-any.pkg.tar.zst"
        SHA512 dfe682110999dfd7e03df50cd2719fbaad7410b327dd918af0606a78dce5cfe6fc719739b3ae147053f4e42bb3f294c2767141f30ccd59e5cac90151e5b0b852
        DEPS mingw-w64-x86_64-tcl
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-xz-5.6.2-2-any.pkg.tar.zst"
        SHA512 2cfb3ef65c0dde9765631c98d5cd2c3ee130b0ed8c3d095ac28de58d062f2b52b9032cb473c672d6b744d8e1dbc0009b8d3bc763fbe9c9425871c822aa48a8f6
        DEPS mingw-w64-x86_64-gettext-runtime
    )
    z_vcpkg_acquire_msys_declare_package(
        URL "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-zlib-1.3.1-1-any.pkg.tar.zst"
        SHA512 1336cd0db102af495d8bbfc6a1956f365750b19d2377fe809e9b26f61a8a6600394e7343677645c5743f4974161535dad5c0503ff50f6126d27bb927754e7320
    )
endmacro()
