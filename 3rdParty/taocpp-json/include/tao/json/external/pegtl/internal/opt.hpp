// Copyright (c) 2014-2020 Dr. Colin Hirsch and Daniel Frey
// Please see LICENSE for license or visit https://github.com/taocpp/PEGTL/

#ifndef TAO_JSON_PEGTL_INTERNAL_OPT_HPP
#define TAO_JSON_PEGTL_INTERNAL_OPT_HPP

#include <type_traits>

#include "../config.hpp"

#include "duseltronik.hpp"
#include "seq.hpp"
#include "skip_control.hpp"
#include "trivial.hpp"

#include "../apply_mode.hpp"
#include "../rewind_mode.hpp"

#include "../analysis/generic.hpp"

namespace TAO_JSON_PEGTL_NAMESPACE::internal
{
   template< typename... Rules >
   struct opt;

   template<>
   struct opt<>
      : trivial< true >
   {
   };

   template< typename... Rules >
   struct opt
   {
      using analyze_t = analysis::generic< analysis::rule_type::opt, Rules... >;

      template< apply_mode A,
                rewind_mode,
                template< typename... >
                class Action,
                template< typename... >
                class Control,
                typename Input,
                typename... States >
      [[nodiscard]] static bool match( Input& in, States&&... st )
      {
         (void)duseltronik< seq< Rules... >, A, rewind_mode::required, Action, Control >::match( in, st... );
         return true;
      }
   };

   template< typename... Rules >
   inline constexpr bool skip_control< opt< Rules... > > = true;

}  // namespace TAO_JSON_PEGTL_NAMESPACE::internal

#endif
